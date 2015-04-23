# Basic ELMO Production Setup Guide

This guide assumes you have an Ubuntu server up and running (version 14.04 recommended) and have ssh'ed to the server as a user with sudo privileges.

It also assumes you have a domain name (e.g. yoursite.example.com) pointing to the Ubuntu server's IP address. Port 443 on the server should be open to the world.

For security reasons, it is not recommended to install ELMO as the `root` user.

### Install dependencies

    sudo apt-get update && sudo apt-get -y upgrade
    sudo apt-get -y install nano git-core curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev python-software-properties nodejs sphinxsearch memcached

### Get ELMO source code and change into project directory

    git clone https://github.com/thecartercenter/elmo
    cd elmo

### Install rbenv, Ruby, and Bundler

    git clone git://github.com/sstephenson/rbenv.git .rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.bashrc
    git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
    echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc
    exec $SHELL
    rbenv install `cat .ruby-version`
    echo "gem: --no-ri --no-rdoc" > ~/.gemrc
    gem install bundler

### Install Nginx and Passenger

    gpg --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
    gpg --armor --export 561F9B9CAC40B2F7 | sudo apt-key add -
    # Add HTTPS support to APT
    sudo apt-get -y install apt-transport-https
    # Add the passenger repository
    sudo sh -c "echo 'deb https://oss-binaries.phusionpassenger.com/apt/passenger trusty main' >> /etc/apt/sources.list.d/passenger.list"
    sudo chown root: /etc/apt/sources.list.d/passenger.list
    sudo chmod 600 /etc/apt/sources.list.d/passenger.list
    sudo apt-get update
    # Install nginx and passenger
    sudo apt-get -y install nginx-full passenger

### Configure Nginx

    sudo nano /etc/nginx/nginx.conf

Copy in the contents of [this config file](nginx.conf). Change `yoursite.example.com` to your hostname.

### Install MySQL and create database

Choose and save separate passwords for the `root` and `elmo` MySQL users you're about to create.

    sudo apt-get install mysql-server mysql-client libmysqlclient-dev
    mysql -u root -p
    create database elmo_production;
    # NOTE: Replace xxx with your elmo user password.
    grant all privileges on elmo_production.* to elmo@localhost identified by 'xxx';
    exit

### Enter ELMO configuration

    cp config/database.yml.example config/database.yml
    nano config/database.yml

Enter your database password under the 'production' section, save, and exit.

    cp config/initalizers/local_config.rb.example config/initalizers/local_config.rb
    nano config/initalizers/local_config.rb

Enter sensible values for the settings in the file. Entering a functioning email server is important as ELMO relies on email to send broadcasts, and registration info, and password reset requests. Once you have ELMO running, you can test your email setup by requesting a password reset for your user. Save and exit when you're done.

### Upload SSL certificate

ELMO requires a valid SSL certificate for general security and to comply with ODK Collect's requirement for same. Free SSL certificates are widely available nowadays. Try [here](https://google.com/search?q=free+ssl+certificate).

    sudo mkdir /etc/nginx/ssl
    sudo chmod 400 /etc/nginx/ssl
    sudo nano /etc/ngnix/ssl.crt

Paste contents of your `.crt` file, save, and exit.

    sudo nano /etc/nginx/ssl.key

Paste contents of your `.key` file, save, and exit.

### Final config

    # Setup cron jobs
    bundle exec whenever -i elmo
    # Build search indices
    bundle exec rake ts:rebuild
    # Create admin user
    bundle exec rake db:create_admin
    # Restart server
    sudo service nginx restart

### Login and enjoy!

Visit **https://yourdomain.example.org** in your browser (replace with your real hostname). The ELMO login screen should appear. Login with username admin, password temptemp. Change the password immediately by clicking on 'admin' in the top right.

See the [ELMO Documentation](http://getelmo.org/documentation/start/) for help on using your new ELMO instance!

### Troubleshooting

If the above is not successful, contact info@getelmo.org or info@sassafras.coop for assistance.