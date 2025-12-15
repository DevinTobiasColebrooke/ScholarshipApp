namespace :email_outreach do
  desc "Check Gmail inbox for replies and save them to the database"
  task check_inbox: :environment do
    puts "\n" + "="*80
    puts "CHECKING INBOX FOR REPLIES"
    puts "="*80

    begin
      InboxSyncService.sync
      puts "\n✓ Sync process finished."
      puts "  Check the 'Needs Response' tab in your tracker."
    rescue => e
      puts "\n✗ Error: #{e.message}"
      puts e.backtrace.first(5)
    end
  end
end
