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
    url = "#{url}-#{3600* (Time.now.to_i / 3600)}"
    if result = settings.dalli.get(hash) 
      puts "GOT CACHED #{url}"
      result
    else
      puts "NO CACHED #{url}"
      grab = open(url).read
      settings.dalli.set hash, grab
      grab
    end
  end

  def is_a_candidate? node
    text = node.inner_text
    text.include?("'s") || text.include?(" and ") || text.include?("s'")
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

    if !text.sub!(" and ", ", and ")
      if !text.sub!("'s", ["s","s'"].shuffle(random: @random).first)
        if !text.sub!("s'","s's")
        end
      end
    end
    node.content = text
  end

  def deface_nodes nodes
    nodes.each do |node|
      deface_node node
    end
  end

  get %r{.*} do
    cache_control :public, max_age: 5
    @random = Random.new(Digest::MD5.hexdigest(url).to_i(16))
    subbed = grab_url("http://www.theguardian.com#{request.path}").gsub('theguardian','tehguardian').gsub("The Guardian", "Teh Guardian").gsub("the Guardian", "teh Guardian")
    doc = Nokogiri::HTML(subbed)
    candidates = gather_candidates doc.css("#content")
    to_deface = pick_nodes candidates
    deface_nodes to_deface
    doc.to_html
  end
end