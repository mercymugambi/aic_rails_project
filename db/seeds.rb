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
