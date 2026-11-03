class SiteSettingsDocument
  # Reading one field of a section: each helper checks the value, records a readable error, and copies the
  # cleaned value into the output only when the field was sent.
  module Fields
    private

    # A string, trimmed. nil counts as empty. Stored only when sent.
    def take_text(source, out, key, where, **rules)
      max, required = rules.values_at(:max, :required)
      value = source[key].nil? ? '' : source[key]
      return add(where, 'must be text') unless value.is_a?(String)

      value = value.strip
      return add(where, required) if required && value.empty?

      add(where, "must be #{max} characters or fewer") if value.length > max
      out[key] = value if source.key?(key)
    end

    def take_web_link(source, out, key, where)
      take_text(source, out, key, where, max: MAX_URL)
      check(out[key], where, WEB_LINK) { |url| web_link?(url) }
    end

    def take_boolean(source, out, key, where)
      return unless source.key?(key)
      return add(where, 'must be true or false') unless [true, false].include?(source[key])

      out[key] = source[key]
    end

    def take_choice(source, out, key, where, choices)
      return unless source.key?(key)
      return add(where, "must be one of #{choices.join(', ')}") unless choices.include?(source[key])

      out[key] = source[key]
    end

    # "YYYY-MM-DD" and a real day, or empty (stored as nil).
    def take_date(source, out, key, where)
      return unless source.key?(key)

      value = source[key].is_a?(String) ? source[key].strip.presence : source[key]
      return out[key] = nil if value.nil?
      return out[key] = value if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && real_date?(value)

      add(where, 'must be a real date written YYYY-MM-DD')
    end

    def real_date?(value)
      Date.iso8601(value)
      true
    rescue Date::Error
      false
    end

    def web_link?(value)
      uri = URI.parse(value)
      uri.is_a?(URI::HTTP) && uri.host.to_s.include?('.')
    rescue URI::InvalidURIError
      false
    end

    # "/events", but not "//other-site.com", which browsers treat as another website.
    def site_path?(value)
      value.match?(%r{\A/(?!/)\S*\z})
    end

    # Adds an error when a non-empty value fails the block.
    def check(value, where, message)
      add(where, message) if value.present? && !yield(value)
    end

    def group(value, where)
      return value if value.is_a?(Hash)

      add(where, 'must be a group of settings')
    end

    def name_of(value, fallback)
      (value.strip.presence if value.is_a?(String)) || fallback
    end

    # Always returns nil, so callers can `return add(...)`.
    def add(where, message)
      @errors << "#{where}: #{message}" unless @errors.include?("#{where}: #{message}")
      nil
    end
  end
end
