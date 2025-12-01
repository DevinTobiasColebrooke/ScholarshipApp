# This file loads all rake tasks from the email_outreach directory.
Dir[Rails.root.join('lib', 'tasks', 'email_outreach', '*.rake')].each { |r| import r }
