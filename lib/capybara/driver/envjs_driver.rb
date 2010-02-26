require 'rack/test'

class Capybara::Driver::Envjs < Capybara::Driver::Base
  class Node < Capybara::Node
    def text
      node.innerText
    end

    def [](name)
      value = if name.to_sym == :class
        node.className
      else
        node.getAttribute(name.to_s)
      end
      return value if value and not value.to_s.empty?
    end

    def [](name)
      attr_name = name.to_s
      attr_name == "class" and attr_name = "className"
      case
      when 'select' == tag_name && 'value' == attr_name
        if node['multiple']
          all_unfiltered(".//option[@selected='selected']").map { |option| option.node.innerText  }
        else
          node.value
        end
#      when 'input' == tag_name && 'checkbox' == type && 'checked' == attr_name
#         node[attr_name] == 'checked' ? true : false
      else
        node[attr_name]
      end
    end

    def set(value)
      case node.tagName
      when "TEXTAREA"
        node.innerText = value
      else
        case node.getAttribute("type")
        when "checkbox", "radio"; node.checked = value
        else; node.setAttribute("value",value)
        end
      end
    end

    def select(option)
      option_node = all_unfiltered("//option[text()='#{option}']") || all_unfiltered("//option[contains(.,'#{option}')]")
      option_node[0].node.selected = true
    rescue Exception => e
      # print e
      options = all_unfiltered(".//option").map { |o| "'#{o.text}'" }.join(', ')
      raise Capybara::OptionNotFound, "No such option '#{option}' in this select box. Available options: #{options}"
    end

    def unselect(option)
      if !node['multiple']
        raise Capybara::UnselectNotAllowed, "Cannot unselect option '#{option}' from single select box."
      end

      begin
        option_node = (all_unfiltered("//option[text()='#{option}']") || all_unfiltered("//option[contains(.,'#{option}')]")).first
        option_node.node.selected = false
      rescue Exception => e
        # print e
        options = all_unfiltered(".//option").map { |o| "'#{o.text}'" }.join(', ')
        raise Capybara::OptionNotFound, "No such option '#{option}' in this select box. Available options: #{options}"
      end
    end

    def click
      _event(self,"MouseEvent",'click',true,true)
    end

    def drag_to(element)
      _event(self,"MouseEvent",'mousedown',true,true)
      _event(element,"MouseEvent",'mousemove',true,true)
      _event(element,"MouseEvent",'mouseup',true,true)
    end

    def tag_name
      node.tagName.downcase
    end

    def visible?
      all_unfiltered("./ancestor-or-self::*[contains(@style, 'display:none') or contains(@style, 'display: none')]").empty?
    end

    def all_unfiltered selector
      window = @driver.browser["window"]
      null = @driver.browser["null"]
      type = window["XPathResult"]["ANY_TYPE"]
      result_set = window.document.evaluate selector, node, null, type, null
      nodes = []
      while n = result_set.iterateNext()
        nodes << Node.new(@driver, n)
      end
      nodes
    end

    def trigger event
      # FIX: look up class and attributes
      _event(self, "", event.to_s, true, true )
    end

    private

    def _event(target,cls,type,bubbles,cancelable)
      e = @driver.browser["document"].createEvent(cls);
      e.initEvent(type,bubbles,cancelable);
      target.node.dispatchEvent(e);
    end

  end

  include ::Rack::Test::Methods
  attr_reader :app

  alias_method :response, :last_response
  alias_method :request, :last_request

  def initialize(app)
    @app = app

    master_load = browser.master["load"]

    browser.master["load"] = proc do |*args|
      if args.size == 2 and args[1].to_s != "[object split_global]"
        file, window = *args
        get(file, {}, env)
        window["evaluate"].call response.body
      else
        master_load.call *args
      end
    end

    browser["window"]["$envx"]["connection"] =
    browser.master["connection"] = @connection = proc do |*args|
      xhr, responseHandler, data = *args
      url = xhr.url.sub %r{^http://example.com}, ""
      params = data || {}
      method = xhr["method"].downcase.to_sym
      e = env;
      if method == :post or method == :put
        e.merge! "CONTENT_TYPE" => xhr.headers["Content-Type"]
      end
      if e["CONTENT_TYPE"] =~ %r{^multipart/form-data;}
        e["CONTENT_LENGTH"] ||= params.length
      end
      begin
        # puts "send #{method} #{url} #{params}"
        send method, url, params, e
        while response.status == 302
          params = {}
          method = :get
          url = response.location
          # puts "redirect #{method} #{url} #{params}"
          send method, url, params, e
        end
      rescue Exception => e
        print "got #{e} #{response.inspect}\n"
        raise e
      end
      @source = response.body
      response.headers.each do |k,v|
        xhr.responseHeaders[k] = v
      end
      xhr.status = response.status
      xhr.responseText = response.body
      responseHandler.call
    end
  end

  def visit(path)
    # puts "visit #{path}"
    as_url = URI.parse path
    base = URI.parse "http://example.com"
    path = (base + as_url).to_s
    browser["window"].location.href = path
  end

  def current_url
    browser["window"].location.href
  end
  
  def source
    @source
  end

  def body
    browser["window"].document.xml
  end

  def response_headers
    response.headers
  end

  def find(selector)
    window = browser["window"]
    null = browser["null"]
    type = window["XPathResult"]["ANY_TYPE"]
    # print window.document.xml
    result_set = window.document.evaluate selector, window.document, null, type, null
    nodes = []
    while n = result_set.iterateNext()
      nodes << Node.new(self, n)
    end
    nodes
  end

  def wait?; true; end

  def wait_until max
    fired, wait = *browser["Envjs"].wait(-max*1000)
    raise Capybara::TimeoutError if !fired && wait.nil?
  end

  def evaluate_script(script)
    browser["window"]["evaluate"].call(script)
  end

  def browser
    unless @_browser
      require 'johnson/tracemonkey'
      require 'envjs/runtime'
      @_browser = Johnson::Runtime.new :size => 0x4000000
      @_browser.extend Envjs::Runtime
    end
    
    @_browser
  end

  def obeys_absolute_xpath
    true
  end

  def has_shortcircuit_timeout
    true
  end

private

  def env
    env = {}
    begin
      env["HTTP_REFERER"] = request.url
    rescue Rack::Test::Error
      # no request yet
    end
    env
  end

end
