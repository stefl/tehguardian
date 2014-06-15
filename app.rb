require 'rubygems'
Bundler.require

require 'open-uri'

class TehGuardian < Sinatra::Base

  dalli_client = Dalli::Client.new
  set :dalli, dalli_client
  use Rack::Cache, verbose: true, metastore: dalli_client, entitystore: dalli_client
  
  configure :development do
    enable :logging, :dump_errors, :raise_errors
  end

  def grab_url url
    hash = Digest::MD5.hexdigest url
    hash = "#{hash}-#{3600* (Time.now.to_i / 3600)}"
    if result = settings.dalli.get(hash) 
      logger.info "GOT CACHED #{url}"
      result
    else
      logger.info "NO CACHED #{url}"
      grab = open(url).read
      settings.dalli.set hash, grab
      grab
    end
  end

  def is_a_candidate? node
    text = node.inner_text
    text.include?("'s") || text.include?("they're") || text.include?(" and ") || text.include?("s'")
  end

  def gather_candidates node
    candidates = []
    if node.children.empty?
      return node if is_a_candidate?(node)
    else
      node.children.each do |child|
        candidates << gather_candidates(child) 
      end
    end
    candidates.flatten.compact
  end

  def pick_nodes nodes
    nodes.shuffle(random: @random)[0..4]
  end

  def deface_node node
    text = node.inner_text

    what_happened = (
      
      if text.sub!("'s", ["s","s'"].shuffle(random: @random).first)
        "A stray apostrophe"
      elsif text.sub!("they're", ["their","there"].shuffle(random: @random).first)
        "A dodgy they're"
      elsif text.sub!(" and ", ", and ")
        "An oxford comma"
      elsif !text.sub!("s'",["s's","s"])
        "A mistaken plural apostrophe"
      end
    )
    node.content = text
    what_happened
  end

  def deface_nodes nodes
    actions = []
    nodes.each do |node|
      actions << deface_node(node)
    end
    actions
  end

  def add_actions_to_footer actions, doc
    what = Nokogiri::XML::Node.new "p", doc
    what.content = "This is a hack by @Stef. Try to spot the deliberate mistakes? #{actions.join(". ")}."
    doc.css("#footer").first.add_child(what)
  end

  get %r{.*} do
    cache_control :public, max_age: 5
    @random = Random.new(Digest::MD5.hexdigest(url).to_i(16))
    subbed = grab_url("http://www.theguardian.com#{request.path}").gsub('theguardian','tehguardian').gsub("The Guardian", "Teh Guardian").gsub("the Guardian", "teh Guardian")
    doc = Nokogiri::HTML(subbed)
    candidates = gather_candidates doc.css("#content")
    to_deface = pick_nodes candidates
    actions = deface_nodes to_deface
    add_actions_to_footer actions, doc
    doc.to_html
  end
end