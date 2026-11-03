namespace :blog do
  desc 'Delete blog photos uploaded more than 24 hours ago that no post uses, and their files'
  task purge_orphan_images: :environment do
    count = BlogPostImage.purge_orphans
    puts "Deleted #{count} unused blog #{'photo'.pluralize(count)}"
  end
end
