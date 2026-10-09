# JSON shape of an event returned by the Events API.
#
# Use Event.with_attached_cover_image.includes(:created_by) when serializing many events to avoid N+1 queries.
class EventSerializer
  def initialize(event)
    @event = event
  end

  def as_json(*)
    {
      id: event.id,
      title: event.title,
      category: event.category,
      status: event.status,
      featured: event.featured,
      date: event.date,
      end_date: event.end_date,
      start_time: clock(event.start_time),
      end_time: clock(event.end_time),
      location: event.location,
      speaker: event.speaker,
      speaker_role: event.speaker_role,
      audience: event.audience,
      description: event.description,
      cover_image_url: BlogPostSerializer.image_url(event.cover_image),
      registration: event.registration,
      registration_url: event.registration_url,
      capacity: event.capacity,
      seats_taken: event.seats_taken,
      seats_left: event.seats_left,
      registrations_count: event.registrations_count,
      registration_open: event.registration_open?,
      created_by: created_by,
      created_at: event.created_at,
      updated_at: event.updated_at
    }
  end

  private

  attr_reader :event

  # "14:00", the church's wall-clock time, rather than Rails' "2000-01-01T14:00:00.000Z".
  def clock(time)
    time&.strftime('%H:%M')
  end

  def created_by
    user = event.created_by
    return unless user

    { id: user.id, name: [user.firstname, user.lastname].compact_blank.join(' ').presence || user.email }
  end
end
