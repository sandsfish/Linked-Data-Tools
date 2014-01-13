#!/usr/bin/env ruby
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'linkeddata'
require 'sparql/client'
require 'rest_client'
require 'csv'
require 'json'
include RDF

# This is technically a "Web Scutter"
#   http://wiki.foaf-project.org/w/Scutter

def queryEndpoint(endpoint, query, format = "text/csv")
    # output options: "xml" (default), "json", "js", "n3", "text/csv"
  begin  
     rest_response = RestClient.post endpoint, :query => query, :output => format, :timeout => '6000' # if necessary to force charset... :content_type => 'text/plain; charset=utf-8'
     return rest_response
  rescue Exception => e
    puts "There was an error while sending the query to the server"

    # FIXME:  Retry options here for empty response body

    puts e.response
    unless rest_response.nil?
      puts '[' + rest_response + ']'
    end

    return e.response
  end
end

  def queryDBpedia(queryURL)
      # output options: "xml" (default), "json", "js", "n3", "text/csv"
    begin  
       # puts "GETing #{queryURL}"
       rest_response = RestClient.get queryURL, :timeout => '6000' # if necessary to force charset... :content_type => 'text/plain; charset=utf-8'
       return rest_response
    rescue => e
      puts "There was an error while sending the query to the server"
      puts "ERROR RESPONSE:  #{e}"
      unless rest_response.nil?
        puts '[' + rest_response + ']'
      end

      return e.response
    end
end

def dbpediaKeywordSearch(queryTerm, maxHits = 1)
	queryTemplate = "http://lookup.dbpedia.org/api/search.asmx/KeywordSearch?QueryClass=&MaxHits=#{maxHits}&QueryString=#{URI::encode(queryTerm)}"
	response = queryDBpedia(queryTemplate)
	xml = Nokogiri::XML(response.to_str)
end

def dbplGetLabel(xml)
	xml.xpath("//db:Result/db:Label", 'db' => 'http://lookup.dbpedia.org/').each do |type|
  		return type.content
	end
end

def dbplGetURI(xml)
	xml.xpath("//db:Result/db:URI", 'db' => 'http://lookup.dbpedia.org/').each do |type|
  		return type.content
	end	
end

def walk(uri)

  endpoint = 'http://dbpedia.org/sparql'
  stop_uris = ["http://dbpedia.org/resource/Category:Articles", 
               "http://dbpedia.org/resource/Category:Contents", 
               "http://dbpedia.org/resource/Category:Glossaries", 
               "http://dbpedia.org/resource/Category:Portals", 
               "http://dbpedia.org/resource/Category:Indexes_of_topics",
               "http://dbpedia.org/resource/Category:Wikipedia_categories",
               "http://dbpedia.org/resource/Category:Categories_by_parameter",
               "http://dbpedia.org/resource/Category:Wikipedia_administration", 
               "http://dbpedia.org/resource/Category:Wikipedia", 
               "http://dbpedia.org/resource/Category:MediaWiki",
               "http://dbpedia.org/resource/Category:Wikipedia_help", 
               "http://dbpedia.org/resource/Category:Wikipedians", 
               "http://dbpedia.org/resource/Category:Wikipedia_adminship",
               "http://dbpedia.org/resource/Category:Categories_by_topic",
               "http://dbpedia.org/resource/Category:Categories_by_field",
               "http://dbpedia.org/resource/Category:Wikipedia_administration_by_topic",
               "http://dbpedia.org/resource/Category:Wikipedia_maintenance", 
               "http://dbpedia.org/resource/Category:Maintenance_categories",
               "http://dbpedia.org/resource/Category:Lists"]
               # also exclude these partial texts:
               #    http://dbpedia.org/resource/Category:Philosophy     _maintenance_categories...
               #    http://dbpedia.org/resource/Category:Philosophy     _Wikipedia_administration...
  
  # NOTE:  There's something very special about these Category hits.  They represent big jumps in the walk, where you walk into a broad relational structure.

  # print "Pulling #{uri}...  "
  query = "SELECT * WHERE { {<#{uri}> ?p ?o . <#{uri}> <#{RDFS.label}> ?label . } UNION { ?o ?p <#{uri}> . ?o <#{RDFS.label}> ?label . }   FILTER(langMatches(lang(?label), 'EN')) }"  # add binding ?o rdfs:label ?resourceLabel . once we're ready to process the whole result below  
  response = queryEndpoint(endpoint, query, "json")
  # print "Got it...  "

  json = JSON.parse(response.body)
  content_type = response.headers[:content_type][/^[^ ;]+/]

  # Collect all result URIs
  resources = json["results"]["bindings"].map { |result| result["o"]["value"] if result["o"]["value"] =~ /^http:\/\/dbpedia.org\/resource/ }.compact

# Find English label of current node
  label = nil
  json["results"]["bindings"].each do |result|
    unless result["p"].nil?
      if result["p"]["type"] == "uri" && result["p"]["value"] == RDFS.label && result["o"]["xml:lang"] == "en"
        label = result["label"]["value"]
        break
      end
    end
  end

  # As long as there are results...
  unless resources.length == 0
    
    # Choose the next hop and make sure it's not in the stop list
    step = resources[rand(resources.length)]
    until !stop_uris.include?(step)
      step = resources[rand(resources.length)]
    end

    # Output the current node's label, or URI if no english label found
    unless label.nil?
      puts "Node: #{label}"
    else
      puts step
    end

    # Pass next step for walking
    return step
  end
end

term = ARGV.first
puts "Seeding with #{term}..."
xml = dbpediaKeywordSearch(term)
  
print "Found #{term}, "
puts "#{dbplGetLabel(xml)}\n"
next_step = dbplGetURI(xml)

while true do
  next_step = walk(next_step)
end
