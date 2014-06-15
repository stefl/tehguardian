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
    text.include?(" its ") || text.include?("'s") || text.include?("they're") || text.include?(" and ") || text.include?("s'")
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

  def deface_node node, doc
    text = node.inner_text
    a = "<span class='teh'>"
    b = "</span>"
    what_happened = (
      
      if text.sub!("its", "#{a}it's#{b}")
        "An it's, not an its"
      elsif  text.sub!("'s", ["#{a}s#{b}","#{a}s'#{b}"].shuffle(random: @random).first)
        "A stray apostrophe"
      elsif text.sub!("they're", ["#{a}their#{b}","#{a}there#{b}"].shuffle(random: @random).first)
        "A dodgy they're"
      elsif text.sub!(" and ", "#{a}, and #{b}")
        "An oxford comma"
      elsif !text.sub!("s'",["#{a}s's#{b}","#{}s#{b}"])
        "A mistaken plural apostrophe"
      end
    )
    node.swap(text)
    what_happened
  end

  def deface_nodes nodes, doc
    actions = []
    nodes.each do |node|
      actions << deface_node(node, doc)
    end
    actions
  end

  def add_actions_to_footer actions, doc
    what = Nokogiri::XML::Node.new "div", doc
    what['class'] = "teh-footer"
    html = %{<p>This is a hack by <a href='https://twitter.com/stef'>@Stef</a>. Can you spot the deliberate mistakes?</p>}
    html << "<ul>"
    actions.each do |action|
      html << %{<li>#{action}.</li>}
    end
    html << "<p><a href='#' class='teh-hightlight-them'>Highlight them</a> | <a href='http://pieces.stef.io/pieces/tehguardian'>Why?</a></p>"
    what.inner_html = html
    doc.css("body").first.add_child(what)
  end

  def add_css doc
    css = %{
      .teh-footer {
        width: 100%;
        background-color: #eee;
        padding: 2em;
        margin-top: 2em;
        text-align: center;
        font-size: 16px;    
      }

      .teh-footer p, .teh-footer ul, .teh-footer li {
        max-width: 30em;
        margin: auto;
        margin-bottom: 1em;
      }

      .teh-found {
        background-color: yellow;
        padding-left: 1em;
        padding-right: 1em;
      }
      .teh-found:after {
        content: ' - Found!';
      }

      .teh-highlighted {
        background-color: yellow;
        padding-left: 1em;
        padding-right: 1em;
      }
    }
    css_node = Nokogiri::XML::Node.new "style", doc
    css_node['type'] = "text/css"
    css_node.content = css
    doc.css("head").first.add_child(css_node)
  end

  def add_javascript doc
    js = %{
      var nodeList = document.querySelectorAll('.teh');
      for (var i = 0, length = nodeList.length; i < length; i++) {
        if (document.body.addEventListener)
        {
            nodeList[i].addEventListener('click',found,false);
        }
        else
        {
            nodeList[i].attachEvent('onclick',found);//for IE
        }
      }

      var highlightLink = document.querySelectorAll('.teh-hightlight-them')[0];
      if (document.body.addEventListener)
      {
          highlightLink.addEventListener('click',highlight,false);
      }
      else
      {
          highlightLink.attachEvent('onclick',highlight);//for IE
      }

      function found(e)
      {
          e = e || window.event;
          var target = e.target || e.srcElement;
          target.className += ' teh-found';
      }

      function highlight(e)
      {
          e.preventDefault();
          var nodeList = document.querySelectorAll('.teh');
          for (var i = 0, length = nodeList.length; i < length; i++) {
            nodeList[i].className += ' teh-highlighted';
          }
      }
    }
    js_node = Nokogiri::XML::Node.new "script", doc
    js_node['type'] = "text/javascript"
    js_node.content = js
    doc.css("html").first.add_child(js_node)
  end

  get %r{.*} do
    cache_control :public, max_age: 5
    @random = Random.new(Digest::MD5.hexdigest(url).to_i(16))
    subbed = grab_url("http://www.theguardian.com#{request.path}").gsub('theguardian','tehguardian').gsub("The Guardian", "Teh Guardian").gsub("the Guardian", "teh Guardian")
    doc = Nokogiri::HTML(subbed)
    candidates = gather_candidates doc.css("#article-body-blocks, #main-article-info")
    to_deface = pick_nodes candidates
    actions = deface_nodes to_deface, doc
    add_actions_to_footer actions, doc
    add_javascript doc
    add_css doc
    doc.to_html
  end
end