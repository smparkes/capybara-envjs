if false # for testing ... but seems okay
  class Thread
    def self.start
      puts caller(0)
      raise "hell"
    end
    def initialize *args
      puts caller(0)
      raise "hell"
    end
  end

  module Timeout
    def timeout *args
      # p "!!! #{args.inspect}"
      # puts caller(0)
      return yield
      raise "hell #{args.inspect}"
    end
    module_function :timeout
  end
end

class Capybara::Driver::Envjs < Capybara::Driver::Base
  class Node < Capybara::Driver::Node
    def text
      native.innerText
    end

    def [](name)
      attr_name = name.to_s
      attr_name == "class" and attr_name = "className"
      case
      when 'select' == tag_name && 'value' == attr_name
        if native['multiple']
          all_unfiltered(".//option[@selected='selected']").map { |option| option.native.innerText  }
        else
          native.value
        end
      else
        native[attr_name]
      end
    end

    def value
      if tag_name == 'textarea'
        native.innerText
      else
        self[:value]
      end
    end

    def set(value)
      case native.tagName
      when "TEXTAREA"
        native.innerText = value
      else
        case native.getAttribute("type")
        when "checkbox", "radio"
          native.click if native.checked != value
        else; native.setAttribute("value",value)
        end
      end
    end

    def select_option
      native.selected = true
    end

    def unselect_option
      if !select_node['multiple']
        raise Capybara::UnselectNotAllowed, "Cannot unselect option from single select box."
      end
      native.removeAttribute('selected')
    end

    def click
      _event(self,"MouseEvents",'click',true,true, :button => 1)
    end

    def drag_to(element)
      # distance stuff is arbitrary at this point, to make jquery.ui happy ...
      _event(self,"MouseEvents",'mousedown',true,true, :button => 1, :pageX => 0, :pageY => 0)
      _event(element,"MouseEvents",'mousemove',true,true, :button => 1, :pageX => 1, :pageY => 1)
      _event(element,"MouseEvents",'mousemove',true,true, :button => 1, :pageX => 0, :pageY => 0)
      _event(element,"MouseEvents",'mouseup',true,true, :button => 1, :pageX => 0, :pageY => 0)
    end

    def tag_name
      native.tagName.downcase
    end

    def visible?
      all_unfiltered("./ancestor-or-self::*[contains(@style, 'display:none') or contains(@style, 'display: none')]").empty?
    end

    def all_unfiltered selector
      window = @driver.browser["window"]
      null = @driver.browser["null"]
      type = window["XPathResult"]["ANY_TYPE"]
      result_set = window.document.evaluate selector, native, null, type, null
      nodes = []
      while n = result_set.iterateNext()
        nodes << Node.new(@driver, n)
      end
      nodes
    end

    def find(locator)
      all_unfiltered locator
    end

    def trigger event
      # FIX: look up class and attributes
      _event(self, "", event.to_s, true, true )
    end

    private

    # a reference to the select node if this is an option node
    def select_node
      find('./ancestor::select').first
    end

    def _event(target,cls,type,bubbles,cancelable,attributes = {})
      e = @driver.browser["document"].createEvent(false && cls || ""); # disabled for now
      e.initEvent(type,bubbles,cancelable);
      attributes.each do |k,v|
        e[k.to_s] = v
      end
      target.native.dispatchEvent(e);
    end

  end

  attr_reader :app

  def rack_test?
    # p "rt?", app_host, default_url, (app_host == default_url)
    app_host == default_url
  end

  def default_host
    (Capybara.default_host || "www.example.com")
  end

  def default_url
    "http://"+default_host
  end

  def app_host
    (ENV["CAPYBARA_APP_HOST"] || Capybara.app_host || default_url)
  end

  def initialize(app)

    if rack_test?
      require 'rack/test'
      class << self; self; end.instance_eval do
        include ::Rack::Test::Methods
        alias_method :response, :last_response
        alias_method :request, :last_request
        define_method :build_rack_mock_session do
          # p default_host
          Rack::MockSession.new(app, default_host)
        end
      end
    end

    @app = app

    master_load = browser.master["load"]

    if rack_test?
      browser.master["load"] = proc do |*args|
        if args.size == 2 and args[1].to_s != "[object split_global]"
          file, window = *args
          body = nil
          if file.index(app_host) == 0
            get(file, {}, env)
            body = response.body
          else
            body = Net::HTTP.get(URI.parse(file))
          end
          window["evaluate"].call body
        else
          master_load.call *args
        end
      end

      browser["window"]["$envx"]["connection"] =
      browser.master["connection"] = @connection = proc do |*args|
        xhr, responseHandler, data = *args
        url = xhr.url
        params = data || {}
        method = xhr["method"].downcase.to_sym
        e = env;
        if method == :post or method == :put
          e.merge! "CONTENT_TYPE" => xhr.headers["Content-Type"]
        end
        e.merge! "HTTP_ACCEPT" => xhr.headers["Accept"] if xhr.headers["Accept"]
        if e["CONTENT_TYPE"] =~ %r{^multipart/form-data;}
          e["CONTENT_LENGTH"] ||= params.length
        end
        times = 0
        begin
          # p url, app_host
          if url.index(app_host) == 0
            url.slice! 0..(app_host.length-1)
          end
          # p url
          # puts "send #{method} #{url} #{params} #{e}"
          send method, url, params, e
          # p "after" #, response
          while response.status == 302 || response.status == 301
            if (times += 1) > 5
              raise Capybara::InfiniteRedirectError, "redirected more than 5 times, check for infinite redirects."
            end
            params = {}
            method = :get
            url = response.location
            if url.index(app_host) == 0
              url.slice! 0..(app_host.length-1)
            end
            # puts "redirect #{method} #{url} #{params}"
            send method, url, params, env
          end
        rescue Exception => e
          # print "got #{e} #{response.inspect}\n"
          raise e
        end
        @source = response.body
        response.headers.each do |k,v|
          xhr.responseHeaders[k] = v
        end
        xhr.status = response.status
        xhr.responseText = response.body
        xhr.readyState = 4
        if url.index(app_host) == 0
          url.slice! 0..(app_host.length-1)
        end
        if url.slice(0..0) == "/"
          url = app_host+url
        end
        xhr.__url = url
        responseHandler.call
      end
    end
  end

  def visit(path)
    as_url = URI.parse path
    base = URI.parse app_host
    path = (base + as_url).to_s
    # p path
    browser["window"].location.href = path
  end

  def current_url
    browser["window"].location.href
  end

  def source
    browser["window"].document.__original_text__
  end

  def body
    browser["window"].document.xml
  end

  def cleanup!
    clear_cookies
  end

  class Headers
    def initialize hash
      @hash = hash
    end
    def [] key
      pair = @hash.find { |pair| pair[0].downcase == key.downcase }
      pair && pair[1]
    end
  end

  def response_headers
    Headers.new(browser["window"]["document"]["__headers__"])
  end

  def status_code
    response.status
  end

  def find(selector)
    window = browser["window"]
    null = browser["null"]
    type = window["XPathResult"]["ANY_TYPE"]
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

  def execute_script(script)
    browser["window"]["evaluate"].call(script)
    nil
  end

  def evaluate_script(script)
    browser["window"]["evaluate"].call(script)
  end

  def browser
    unless @_browser
      require 'johnson/tracemonkey'
      require 'envjs/runtime'
      @_browser = Johnson::Runtime.new :size => Integer(ENV["JOHNSON_HEAP_SIZE"] || 0x4000000)
      @_browser.extend Envjs::Runtime
    end

    @_browser
  end

  def has_shortcircuit_timeout?
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

Capybara.register_driver :envjs do |app|
  Capybara::Driver::Envjs.new(app)
end
