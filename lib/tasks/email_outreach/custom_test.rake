namespace :email_outreach do
  desc "Send a test email to dtcolebrooke@gmail.com from johanna@johannalucilleroberts.com"
  task test_dtc: :environment do
    target_email = "dtcolebrooke@gmail.com"

    puts "\n" + "="*80
    puts "CUSTOM EMAIL TEST"
    puts "="*80
    puts "Configuration Check:"
    puts "  Delivery Method: #{ActionMailer::Base.delivery_method.inspect}"
    puts "  Perform Deliveries: #{ActionMailer::Base.perform_deliveries}"
    puts "  Raise Delivery Errors: #{ActionMailer::Base.raise_delivery_errors}"

    puts "\nAttempting to send email..."
    puts "  To:   #{target_email}"
    puts "  From: johanna@johannalucilleroberts.com (via SMTP config)"

    # The mailer requires an Organization and OutreachContact object to populate fields.
    # We grab the first organization or create a dummy one if the DB is empty.
    org = Organization.first
    unless org
      puts "  ! No organizations found in DB. Creating a temporary placeholder."
      org = Organization.create!(name: "Test Organization", ein: "00-0000000")
    end
    puts "  Using Organization context: #{org.name}"

    # Create an ephemeral contact object (we don't save it to DB to avoid clutter)
    # This provides the necessary interface for OutreachMailer.
    contact = OutreachContact.new(
      organization: org,
      status: "ready_for_email_outreach",
      contact_email: target_email,
      campaign_name: "Custom Test Task"
    )

    begin
      # Build the email
      mail = OutreachMailer.scholarship_inquiry(contact)

      puts "  Subject: \"#{mail.subject}\""

      # Send the email
      print "  Sending... "
      mail.deliver_now
      puts "✓ SUCCESS"

      puts "\nPlease check the inbox for #{target_email}."

    rescue => e
      puts "✗ FAILED"
      puts "\nError Details:"
      puts "  #{e.class}: #{e.message}"
      puts "\nBacktrace:"
      puts e.backtrace.first(5).map { |line| "  #{line}" }

      puts "\nTroubleshooting Tips:"
      puts "1. Ensure 'johanna@johannalucilleroberts.com' credentials are correct in credentials.yml.enc"
      puts "2. Check config/environments/development.rb SMTP settings"
    end

    puts "="*80 + "\n"
  end
end
