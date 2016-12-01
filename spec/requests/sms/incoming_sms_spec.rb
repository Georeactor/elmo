require "spec_helper"

describe "incoming sms", :sms do
  include IncomingSmsSupport

  REPLY_VIA_RESPONSE_STYLE_ADAPTER = "FrontlineSms"

  let(:form) { setup_form(questions: %w(integer integer), required: true) }
  let(:form_code) { form.current_version.code }
  let(:wrong_code) { form_code.sub(form.code[0], form.code[0] == "a" ? "b" : "a") }
  let(:bad_incoming_token) { "0" * 32 }

  before :all do
    @user = get_user
  end

  context "with text form" do
    let(:form) { setup_form(questions: %w(text), required: true) }

    it "can accept text answers" do
      assert_sms_response(incoming: "#{form_code} 1.this is a text answer", outgoing: /#{form_code}.+thank you/i)
      # Ensure objects are persisted
      expect(Sms::Incoming.count).to eq 1
      expect(Sms::Reply.count).to eq 1
    end
  end

  context "with long_text form" do
    let(:form) { setup_form(questions: %w(long_text), required: true) }

    it "can accept long_text answers" do
      assert_sms_response(
        incoming: "#{form_code} 1.this is a text answer that is very very long",
        outgoing: /#{form_code}.+thank you/i)
    end
  end

  context "with decimal form" do
    let(:form) { setup_form(questions: %w(decimal), required: true) }

    it "long decimal answers have value truncated" do
      assert_sms_response(
        incoming: "#{form_code} 1.sfsdfsdfsdfsdf",
        outgoing: /Sorry.+answer 'sfsdfsdfsd...'.+question 1.+form '#{form_code}'.+not a valid/)
    end
  end

  context "with integer form" do
    let(:form) { setup_form(questions: %w(integer), required: true) }
    it "long integer answers have value truncated" do
      assert_sms_response(
        incoming: "#{form_code} 1.sfsdfsdfsdfsdf",
        outgoing: /Sorry.+answer 'sfsdfsdfsd...'.+question 1.+form '#{form_code}'.+not a valid/)
    end
  end

  context "with select_one form" do
    let(:form) { setup_form(questions: %w(select_one), required: true) }
    it "long select_one should have value truncated" do
      assert_sms_response(
        incoming: "#{form_code} 1.sfsdfsdfsdfsdf",
        outgoing: /Sorry.+answer 'sfsdfsdfsd...'.+question 1.+form '#{form_code}'.+not a valid option/)
    end
  end

  context "with select_multiple form" do
    let(:form) { setup_form(questions: %w(select_multiple), required: true) }

    it "long select_multiple should have value truncated" do
      assert_sms_response(
        incoming: "#{form_code} 1.sfsdfsdfsdfsdf",
        outgoing: /Sorry.+answer 'sfsdfsdfsd...'.+question 1.+form '#{form_code}'.+contained multiple invalid options/)
    end

    it "message with one invalid option should get error" do
      assert_sms_response(
        incoming: "#{form_code} 1.abh",
        outgoing: /Sorry.+answer 'abh'.+contained the invalid option 'h'/)
    end

    it "message with multiple invalid options should get error" do
      assert_sms_response(
        incoming: "#{form_code} 1.abhk",
        outgoing: /Sorry.+answer 'abhk'.+contained invalid options 'h, k'/)
    end
  end

  it "correct message should get congrats" do
    # response should include the form code
    assert_sms_response(incoming: "#{form_code} 1.15 2.20", outgoing: /#{form_code}.+thank you/i)
  end

  it "GET submissions should be possible" do
    assert_sms_response(method: :get, incoming: "#{form_code} 1.15 2.20", outgoing: /#{form_code}.+thank you/i)
  end

  it "message from automated sender should get no response" do
    assert_sms_response(from: "VODAFONE", incoming: "blah blah junk", outgoing: nil)
    expect(Sms::Reply.count).to eq 0
  end

  context "from unrecognized normal number" do
    it "should get error reply" do
      assert_sms_response(from: "+737377373773", incoming: "#{form_code} 1.x 2.x",
        outgoing: /couldn't find you/)
    end

    context "with missionless url" do
      let(:missionless_url) { true }

      it "should get error reply" do
        assert_sms_response(from: "+737377373773", incoming: "#{form_code} 1.x 2.x",
          outgoing: /couldn't find you/, mission: nil)
      end
    end
  end

  it "message inactive user should get error" do
    @user.activate!(false)
    assert_sms_response(incoming: "#{form_code} 1.x 2.x", outgoing: /couldn't find you/)
  end

  it "message with invalid answer should get error" do
    # this tests invalid answers that are caught by the decoder
    assert_sms_response(
      incoming: "#{form_code} 1.xx 2.20",
      outgoing: /Sorry.+answer 'xx'.+question 1.+form '#{form_code}'.+not a valid/)
  end

  it "bad encoding should get error" do
    # for instance, try to submit with bad form code
    # we don't have to try all the encoding errors b/c that's covered in the decoder test
    assert_sms_response(incoming: "123", outgoing: /not a valid form code/i)
  end

  it "message missing one answer should get error" do
    assert_sms_response(incoming: "#{form_code} 2.20", outgoing: /answer.+required question 1 was.+#{form_code}/)
  end

  it "message missing multiple answers should get error" do
    assert_sms_response(incoming: "#{form_code}", outgoing: /answers.+required questions 1,2 were.+#{form_code}/)
  end

  it "too high numeric answer should get error" do
    # add a maximum constraint to the first question
    form.unpublish!
    form.questions.first.update_attributes!(maximum: 20)
    form.publish!

    # check that it works
    assert_sms_response(incoming: "#{form_code} 1.21 2.21", outgoing: /Must be less than or equal to 20/)
  end

  it "duplicate should result error message" do
    create(:sms_incoming, from: @user.phone, body: "#{form_code} 1.15 2.20", sent_at: Time.now)
    Timecop.travel(10.minutes) do
      assert_sms_response(incoming: "#{form_code} 1.15 2.20", outgoing: /duplicate/)
      expect(Sms::Incoming.count).to eq 2
    end
  end

  it "reply should be in correct language" do
    # set user lang pref to french
    @user.pref_lang = "fr"
    @user.save(validate: false)

    # now try to send to the new form (won't work b/c no permission)
    assert_sms_response(incoming: "#{form_code} 1.15 2.b", outgoing: /votre.+#{form_code}/i)
  end

  it "fails when the incoming SMS token is incorrect" do
    begin
      token = SecureRandom.hex
    end while token == get_mission.setting.incoming_sms_token

    do_incoming_request(
      url: "/m/#{get_mission.compact_name}/sms/submit/#{token}",
      incoming: { body: "#{form_code} 1.15 2.20", adapter: REPLY_VIA_RESPONSE_STYLE_ADAPTER })
    expect(@response.status).to eq(401)
  end

  context "with failing Twilio validation" do
    let(:twilio_adapter) { Sms::Adapters::TwilioAdapter.new }

    before do
      expect(twilio_adapter).to receive(:validate).and_raise(Sms::Error)
      expect(Sms::Adapters::Factory.instance).to receive(:create_for_request).and_return(twilio_adapter)
    end

    it "should raise error" do
      expect do
        do_incoming_request(url: "/m/#{get_mission.compact_name}/sms/submit/#{get_mission.setting.incoming_sms_token}",
          from: @user.phone, incoming: {body: "#{form_code} 1.15 2.20", adapter: "TwilioSms"})
      end.to raise_error(Sms::Error)
    end
  end

  context "with SMS relay enabled" do
    let(:users) { create_list(:user, 2) }
    let(:group) { create(:user_group, users: create_list(:user, 3)) }
    let(:recipients) { users + [group] }
    let(:form) { setup_form(questions: %w(integer text), forward_recipients: recipients) }
    let(:sms_forward) { Sms::Forward.first }
    let(:actual_recipients) { sms_forward.recipient_hashes.map { |hash| hash[:user] } }

    shared_examples_for "sends forwards" do
      it "sends forwards" do
        incoming_body = "#{form_code} 1.15 2.something"
        assert_sms_response(incoming: incoming_body , outgoing: /#{form_code}.+thank you/i)
        expect(sms_forward.body).to eq incoming_body
        expect(actual_recipients).to contain_exactly(*(users + group.users))
        expect(Broadcast.count).to eq 1 # Ensure persisted
      end
    end

    context "normally" do
      it_behaves_like "sends forwards"
    end

    context "with sms authentication enabled" do
      let(:form) { setup_form(questions: %w(integer text), forward_recipients: recipients, authenticate_sms: true) }

      it "strips auth code from forward" do
        incoming_body = "#{auth_code} #{form_code} 1.29 2.something"
        assert_sms_response(incoming: incoming_body, outgoing: /#{form_code}.+thank you/i)
        expect(sms_forward.body).to eq "#{form_code} 1.29 2.something"
      end
    end

    context "with missionless url" do
      let(:missionless_url) { true }
      it_behaves_like "sends forwards"

      context "with invalid token" do
        it "raises error and doesn't persist broacast or forward" do

          do_incoming_request(url: "/sms/submit/#{bad_incoming_token}", from: @user.phone,
            incoming: {body: "#{form_code} 1.15 2.something", })
          expect(@response.status).to eq(401)
          expect(Broadcast.count).to eq 0
          expect(Sms::Forward.count).to eq 0
          expect(Response.count).to eq 0
        end
      end
    end
  end

  context "with no mission in URL" do
    # TODO: I am thinking this is how we should refactor this spec: change assert_sms_response into
    # a custom matcher and define any special request options in a `let`.
    # For now I'm checking request_options in the helper method.
    let(:missionless_url) { true }

    it "should process correctly with valid form code" do
      assert_sms_response(incoming: "#{form_code} 1.15 2.20", outgoing: /#{form_code}.+thank you/i)
      expect(Sms::Incoming.first.mission).to eq get_mission
      expect(Sms::Reply.first.mission).to eq get_mission
    end

    it "should send reply if form not found" do
      assert_sms_response(incoming: "#{wrong_code} 1.15 2.20",
        outgoing: /there is no form with code/, mission: nil)
    end
  end
end
