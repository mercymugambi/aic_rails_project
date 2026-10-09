# AIC Rails Project

Rails 7.0 JSON API backend for the AIC church management application. It provides JWT login, role-based access control (RBAC), church records (members, leadership positions, fellowship groups, events, devotions) and M-Pesa STK Push payments. Data is stored in PostgreSQL.

## Requirements

- Ruby 3.2.2 (pinned in `.ruby-version` and `Gemfile`)
- Bundler
- PostgreSQL 14 or newer

> **Windows:** if several Rubies are installed, make sure Ruby 3.2 comes first on `PATH`. Otherwise Bundler stops with `Your Ruby version is 3.4.x, but your Gemfile specified 3.2.2`. For the current terminal only:
>
> ```powershell
> $env:Path = "C:\Ruby32-x64\bin;" + $env:Path
> ```

## First-time setup

1. Copy `.env.example` to `.env`.
2. Set `DATABASE_PORT` and `DATABASE_PASSWORD` for your local PostgreSQL server. pgAdmin shows the port under the server's *Properties > Connection*.
3. Install gems and create and migrate the databases:

   ```powershell
   bundle install
   bundle exec rails db:prepare
   ```

4. Load the permissions, the `church_admin` role and the super admin user:

   ```powershell
   bundle exec rails db:seed
   ```

## Run the backend

```powershell
bundle exec rails server
```

The API is available at http://localhost:3000. CORS allows a frontend on port 3001 (see `config/initializers/cors.rb`).

## Authentication

1. `POST /api/v1/auth/login` with `{ "user": { "email": "...", "password": "..." } }`.
2. Read the token from the `Authorization: Bearer <token>` response header.
3. Send that header on every protected request. Tokens expire after 24 hours.
4. `DELETE /api/v1/auth/logout` revokes the token.

## API endpoints

| Method | Path | Purpose | Access |
|---|---|---|---|
| POST | `/api/v1/auth/login` | Log in, returns JWT | Public |
| DELETE | `/api/v1/auth/logout` | Revoke JWT | Logged in |
| GET | `/api/v1/users/me` | The logged-in user, with roles and permissions | Logged in |
| GET | `/api/v1/users` | List users | Logged in |
| GET | `/api/v1/users/:id` | Show a user | Logged in |
| POST | `/api/v1/users` | Create a user and assign their roles | Super admin only |
| GET | `/api/v1/roles` | List roles with permissions | Logged in |
| POST | `/api/v1/roles` | Create a role | Super admin or church admin |
| POST | `/api/v1/user_roles` | Assign a role to a user | Super admin or church admin |
| DELETE | `/api/v1/user_roles/:id` | Remove a role from a user | Super admin or church admin |
| GET | `/api/v1/members` | List members (ordered by first, last name) | `manage_members` or `manage_fellowship_groups` |
| GET | `/api/v1/members/:id` | Show a member | `manage_members` |
| POST | `/api/v1/members` | Add a member (`{ "member": {...} }`) | `manage_members` |
| PATCH | `/api/v1/members/:id` | Partial update; `fellowship_group_ids` replaces groups; `user_id` links a login account (`null` unlinks) | `manage_members` (+ `manage_users` to change the link) |
| DELETE | `/api/v1/members/:id` | Delete (409 if linked to a user account) | `manage_members` |
| POST | `/api/v1/members/bulk_destroy` | Delete up to 500 members (`{ "ids": [...] }`) | `manage_members` |
| GET, POST | `/api/v1/devotions` | List / create devotions | Public |
| GET | `/api/v1/events?when=upcoming\|past\|all` | Published and cancelled events (upcoming by default, soonest first), with absolute `cover_image_url`, seat counts and `registration_open` | Public |
| GET | `/api/v1/events?status=all` | Same list including drafts (combines with `when`) | `manage_events` |
| GET | `/api/v1/events/:id` | One event (404 for a draft unless the token has `manage_events`) | Public |
| POST | `/api/v1/events` | Create an event, multipart form data or JSON under `event[...]`, optional `cover_image` (JPG, PNG or WEBP, max 10 MB) | `manage_events` |
| PATCH | `/api/v1/events/:id` | Partial update (only the keys sent change); `remove_cover_image=true` deletes the cover | `manage_events` |
| DELETE | `/api/v1/events/:id` | Delete an event, its RSVPs and its cover photo | `manage_events` |
| POST | `/api/v1/events/:id/registrations` | RSVP (`{ "registration": { "name", "phone", "email", "seats" } }`); at most 5 per connection per 10 minutes | Public |
| GET | `/api/v1/events/:id/registrations` | The RSVPs for an event, oldest first | `manage_events` |
| DELETE | `/api/v1/events/:event_id/registrations/:id` | Remove an RSVP and free its seats | `manage_events` |
| GET, POST | `/api/v1/leadership_positions` | List / create leadership positions | Public |
| GET | `/api/v1/fellowship_groups` | List groups with leader and member count | `manage_fellowship_groups` or `manage_members` |
| GET | `/api/v1/fellowship_groups/:id` | Show a group with its members | `manage_fellowship_groups` or `manage_members` |
| POST, PATCH, DELETE | `/api/v1/fellowship_groups[/:id]` | Create / edit / delete a group (`{ "fellowship_group": {...} }`) | `manage_fellowship_groups` |
| POST | `/api/v1/fellowship_groups/:id/members` | Add members (`{ "member_ids": [...] }`) | `manage_fellowship_groups` or `manage_members` |
| DELETE | `/api/v1/fellowship_groups/:id/members/:member_id` | Remove a member (clears the leader if it was them) | `manage_fellowship_groups` or `manage_members` |
| GET | `/api/v1/gallery_images` | List photos as a plain array, newest `taken_on` first (undated last), each with an absolute `image_url` | Public |
| POST | `/api/v1/gallery_images` | Upload one photo as multipart form data: `gallery_image[image]` (JPG, PNG or WEBP, max 10 MB), `gallery_image[title]`, `gallery_image[category]`, `gallery_image[taken_on]` | `manage_gallery` |
| PATCH | `/api/v1/gallery_images/:id` | Edit `title`, `category`, `taken_on` (`{ "gallery_image": {...} }`; `null` clears category or date) | `manage_gallery` |
| DELETE | `/api/v1/gallery_images/:id` | Delete a photo and its stored file | `manage_gallery` |
| GET | `/api/v1/blog_posts` | Published posts as a plain array, newest `published_on` first, with absolute `cover_image_url` and `read_minutes` | Public |
| GET | `/api/v1/blog_posts?status=all` | Same list including drafts | `manage_blog` |
| GET | `/api/v1/blog_posts/:slug` | A published post, looked up by **slug** (404 for drafts) | Public |
| POST | `/api/v1/blog_posts` | Create a post as multipart form data under `blog_post[...]`; `body` is a JSON string of blocks, `tags[]` repeated, optional `cover_image` (JPG, PNG or WEBP, max 10 MB) | `manage_blog` |
| PATCH | `/api/v1/blog_posts/:id` | Partial update, multipart or JSON (only the keys sent change); `remove_cover_image=true` deletes the cover | `manage_blog` |
| DELETE | `/api/v1/blog_posts/:id` | Delete a post, its cover and the photos in its body | `manage_blog` |
| POST | `/api/v1/blog_post_images` | Upload a photo for a post's body (`blog_post_image[image]`); returns `{ id, url }`, and the body's image block refers to it by `image_id` | `manage_blog` |
| GET | `/api/v1/site_settings` | The website settings document (notice bar, SEO, contact, social links, service times), unwrapped; `{}` until saved | Public |
| PATCH | `/api/v1/site_settings` | Save settings (`{ "site_settings": {...} }`, JSON); each section sent replaces the stored one, others are kept; answers with the whole document | `manage_settings` |
| POST | `/api/v1/payment` | Start an M-Pesa STK Push | Public |
| POST | `/api/v1/callback` | M-Pesa result callback | Public (Safaricom) |

Run `bundle exec rails routes` for the full list, which also includes Devise's password routes.

## Events

Event dates and times are the church's local time (Africa/Nairobi, UTC+3), whatever the server's time zone. An event is upcoming until its last day (`end_date`, or `date` for a one-day event) is over. A draft needs only a title and a date; published and cancelled events also need a category and a description. Only one event can be featured at a time.

How people sign up is set by `registration`: `none`, `rsvp` (on the website, with an optional `capacity`) or `external` (a `registration_url`). Website sign-ups close when the event starts or is full. Each person can sign up once per event: phone numbers are compared with Kenyan forms unified (`0712…`, `+254712…`), and emails ignoring case.

`db:seed` adds four sample upcoming events in development when there are none.

## Blog posts

A post's `body` is an array of blocks: `paragraph` and `heading` (`text`), `quote` (`text`, optional `cite`), `list` (`items`) and `image` (`image_id`, optional `caption`). Other keys are dropped. A draft needs only a title; a published post also needs an excerpt, a category, a publish date and some content. Only one post can be featured at a time, and a post's slug never changes unless a new one is sent, so old links keep working.

Photos inside a post are uploaded first, while the writer is drafting, so some are never used. Delete unused photos older than 24 hours once a day (Windows Task Scheduler locally, or a cron job on the host):

```powershell
bundle exec rails blog:purge_orphan_images
```

## Cloudinary setup (gallery and blog photos)

Gallery and blog photos are stored with Active Storage. When `CLOUDINARY_URL` is set they go to Cloudinary (folder `aic-kabuku/gallery`); without it they are saved on the local disk in `storage/`, so uploads work before Cloudinary is set up.

1. Create a free account at https://cloudinary.com.
2. On the dashboard (Settings > API Keys), copy the **API environment variable**. It looks like `cloudinary://<api_key>:<api_secret>@<cloud_name>`.
3. Add it to `.env`:

   ```
   CLOUDINARY_URL=cloudinary://<api_key>:<api_secret>@<cloud_name>
   ```

4. Restart the Rails server.

New uploads then return `https://res.cloudinary.com/...` image URLs. Photos uploaded before the switch stay on the local disk and keep working. In production, set `CLOUDINARY_URL` in the deployment environment. Never commit real keys.

## Users and access control

- **Super admin** (`users.super_admin = true`) has every permission. It is created by `db/seeds.rb`.
- **Only the super admin creates accounts.** There is no self sign-up. The super admin sends:

  ```json
  POST /api/v1/users
  { "email": "leader@example.com", "password": "secret123", "firstname": "Jane", "lastname": "Doe",
    "role_ids": [1, 2], "member_id": 5 }
  ```

  `role_ids` and `member_id` are optional. The user and their roles are saved together, or not at all.
- **Roles** group **permissions**, for example `manage_events`. Users get roles through `user_roles`.
- Every user response (login, `/users/me`, `/users`) includes `super_admin`, `roles` and `permissions`. The frontend uses **permissions**, not role names, to decide which pages and buttons to show.
- Hiding a page in the frontend is not security. Protect each endpoint in its controller with `authorize!(:permission_name)` or `require_super_admin!` (see `ApplicationController`).

## Project layout

```
app/
  controllers/
    application_controller.rb   # shared authorize! helper, Devise params
    api/v1/                     # all JSON API endpoints (versioned)
      auth/sessions_controller.rb
  models/                       # User, Member, Role, Permission, ... (RBAC + church records)
  views/devise/                 # customized Devise HTML forms and emails
config/
  routes.rb                     # every route, grouped by area
  initializers/devise.rb        # auth + JWT settings
  initializers/cors.rb          # allowed frontend origins
db/
  migrate/                      # schema history (never edit old migrations)
  schema.rb                     # current schema (generated)
  seeds.rb                      # permissions, church_admin role, super admin
```

## Useful commands

```powershell
bundle exec rails db:migrate       # Apply pending migrations
bundle exec rails db:seed          # Load seed data (safe to re-run; resets the super admin password)
bundle exec rails test             # Run the test suite
bundle exec rails routes           # List routes
bundle exec rubocop                # Lint Ruby code (also runs in CI on pull requests)
```

For production, provide a complete `DATABASE_URL` and `RAILS_MASTER_KEY` through the deployment environment instead of committing credentials.
