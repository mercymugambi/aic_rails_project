# The blocks that make up a blog post's text (blog_posts.body, a jsonb array). Allowed shapes:
#
#   { "type" => "paragraph", "text" => "..." }
#   { "type" => "heading",   "text" => "..." }
#   { "type" => "quote",     "text" => "...", "cite" => "John 3:16" }   # cite optional
#   { "type" => "list",      "items" => ["...", "..."] }
#   { "type" => "image",     "image_id" => "<BlogPostImage token>", "caption" => "..." }  # caption optional
#
# Image blocks store only the photo's id; BlogPostSerializer adds a fresh `url` on every read.
module BlogPostBody
  TYPES = %w[paragraph heading quote list image].freeze
  PHOTO_ERROR = "A photo in the post wasn't uploaded properly. Please insert it again.".freeze

  module_function

  # Keeps only the documented keys of known blocks, with whitespace trimmed and blank optional values
  # dropped. Anything it doesn't recognise is returned unchanged so errors_for can report it.
  def normalize(blocks)
    return blocks unless blocks.is_a?(Array)

    blocks.map { |block| normalize_block(block) }
  end

  # Messages a church admin can act on; empty when the blocks are valid. Does not check that image ids
  # exist (BlogPost does, against blog_post_images).
  def errors_for(blocks)
    unless blocks.is_a?(Array)
      return ['The post content must be a list of paragraphs, headings, quotes, lists and photos']
    end

    blocks.each_with_index.filter_map { |block, index| block_error(block, index + 1) }.uniq
  end

  def image_ids(blocks)
    return [] unless blocks.is_a?(Array)

    blocks.filter_map { |block| block['image_id'] if block.is_a?(Hash) && block['type'] == 'image' }
      .grep(String).uniq
  end

  # Words in text, quote citations and list items (not captions).
  def word_count(blocks)
    return 0 unless blocks.is_a?(Array)

    blocks.grep(Hash).sum do |block|
      [block['text'], block['cite'], *Array(block['items'])].grep(String).sum { |words| words.split.size }
    end
  end

  def normalize_block(block)
    return block unless block.is_a?(Hash)

    case block['type']
    when 'paragraph', 'heading' then { 'type' => block['type'], 'text' => trim(block['text']) }.compact
    when 'quote' then { 'type' => 'quote', 'text' => trim(block['text']), 'cite' => optional(block['cite']) }.compact
    when 'list' then { 'type' => 'list', 'items' => trim_items(block['items']) }.compact
    when 'image'
      { 'type' => 'image', 'image_id' => trim(block['image_id']), 'caption' => optional(block['caption']) }.compact
    else block
    end
  end

  def block_error(block, position)
    type = block['type'] if block.is_a?(Hash)
    return "Part #{position} of the post isn't a paragraph, heading, quote, list or photo" unless TYPES.include?(type)
    return if block_complete?(block)

    case type
    when 'list' then "The list in part #{position} of the post has no items"
    when 'image' then PHOTO_ERROR
    else "The #{type} in part #{position} of the post is empty"
    end
  end

  def block_complete?(block)
    case block['type']
    when 'list' then block['items'].is_a?(Array) && block['items'].any? && block['items'].all?(String)
    when 'image' then block['image_id'].is_a?(String)
    else block['text'].is_a?(String)
    end
  end

  # Strings are stripped (blank becomes nil); other values are kept so validation can reject them.
  def trim(value)
    value.is_a?(String) ? value.strip.presence : value
  end

  def trim_items(items)
    items.is_a?(Array) ? items.map { |item| trim(item) }.compact : items
  end

  def optional(value)
    value.strip.presence if value.is_a?(String)
  end
end
