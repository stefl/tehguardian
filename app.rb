require 'rubygems'
Bundler.require

require 'open-uri'

class TehGuardian < Sinatra::Base
  get %r{.*} do
    open("http://www.theguardian.com#{request.path}").read.gsub('theguardian','tehguardian') 
  end
end