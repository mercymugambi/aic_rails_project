# db/seeds.rb

# --- Permissions ---
permissions = [
  { name: 'manage_members', description: 'Create, edit, and delete members' },
  { name: 'manage_users', description: 'Create and manage user accounts' },
  { name: 'manage_roles', description: 'Create roles and assign permissions' },
  { name: 'manage_events', description: 'Create, edit, and delete events' },
  { name: 'manage_devotions', description: 'Create, edit, and delete devotions' },
  { name: 'manage_fellowship_groups', description: 'Create and manage fellowship groups' },
  { name: 'manage_leadership_positions', description: 'Create and manage leadership positions' },
  { name: 'manage_finance', description: 'Manage financial records and payments' },
  { name: 'view_reports', description: 'View reports and analytics' },
  { name: 'manage_sermons', description: 'Upload and manage sermons' },
  { name: 'manage_visitors', description: 'Register and manage visitors' },
  { name: 'manage_appointments', description: 'Manage pastoral appointments' },
  { name: 'manage_gallery', description: 'Upload and manage gallery images' },
  { name: 'manage_blog', description: 'Write, publish and manage blog posts' },
  { name: 'manage_settings', description: 'Manage church settings and configuration' }
]

permissions.each do |perm|
  Permission.find_or_create_by!(name: perm[:name]) do |p|
    p.description = perm[:description]
  end
end
puts "Seeded #{Permission.count} permissions"

# --- Roles ---
church_admin_role = Role.find_or_create_by!(name: 'church_admin') do |r|
  r.description = 'Church Administrator — full access to church management'
end

# Church admin gets all permissions
church_admin_role.permissions = Permission.all
puts "Seeded church_admin role with #{church_admin_role.permissions.count} permissions"

# --- Super Admin User ---
super_admin = User.find_or_initialize_by(email: 'admin@aickabuku.com')
super_admin.password = 'admin@kabukuaic'
super_admin.super_admin = true
super_admin.save!
puts "Super admin user: #{super_admin.email}"

# --- Sample events (development only, and only when there are none) ---
if Rails.env.development? && Event.none?
  today = Event::TIME_ZONE.today
  samples = [
    { title: 'Night of Prayer', category: 'Prayer', date: today + 5, end_date: today + 6,
      start_time: '21:00', end_time: '05:00', location: 'Main Sanctuary & Prayer Hall', featured: true,
      description: 'An overnight vigil of worship, prayer and the Word. Come for an hour or stay the night.' },
    { title: 'Couples & Family Marriage Seminar', category: 'Worship & Services', date: today + 8,
      start_time: '14:00', end_time: '17:30', location: 'Sanctuary Fellowship Hall',
      speaker: 'Elder Samuel & Mary Karanja', speaker_role: 'Family Life Mentors',
      audience: 'Engaged and married couples', registration: 'rsvp', capacity: 80,
      description: 'An afternoon of teaching and honest conversation about building a Christ-centred home.' },
    { title: 'Kabuku Town Outreach', category: 'Outreach', date: today + 14, start_time: '10:00',
      end_time: '15:00', location: 'Kabuku Town Grounds',
      description: 'Sharing the Gospel, free medical checks and a meal with our neighbours.' },
    { title: 'Youth Conference', category: 'Youth', date: today + 20, end_date: today + 22, start_time: '09:00',
      end_time: '16:00', location: 'Youth Fellowship Center', audience: 'Ages 13 to 25',
      registration: 'external', registration_url: 'https://example.com/aic-kabuku-youth-conference',
      description: 'Three days of worship, teaching and fellowship for young people.' }
  ]
  samples.each { |attributes| Event.create!(attributes.merge(created_by: super_admin)) }
  puts "Seeded #{samples.size} sample events"
end
