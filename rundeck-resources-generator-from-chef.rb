#!/usr/bin/env ruby
# Inspired on https://github.com/oswaldlabs/chef-rundeck

gem 'chef', '12.5.1'
require 'uri'
require 'chef'

class NilClass
    def [](* args)
        nil
    end
end

class ResourcesGenerator

    def initialize(url=nil)
        Chef::Config.from_file("#{ENV['HOME']}/.chef/knife.rb")
        @rest = Chef::REST.new(url || Chef::Config[:chef_server_url])
    end

    def search(type=:node, query='*.*', qs={}, node_attr={})
        raise ArgumentError, "Type must be a string or a symbol!" unless (type.kind_of?(String) || type.kind_of?(Symbol))

        query_string = "search/#{type}?q=#{escape(qs[:query])}&sort=#{escape(qs[:sort])}&start=#{escape(qs[:start])}&rows=#{escape(qs[:rows])}"
        if node_attr
            response = @rest.post_rest(query_string, node_attr)
            response_rows = response['rows']
        end
    end

    def save(nodes, resource_file)
        raise ArgumentError, "Type must be an Array" unless (nodes.kind_of?(Array))

        username = "pedeploy"
        saved_nodes = 0

        temp_resource_file = resource_file + '.tmp'
        file = File.open(temp_resource_file, 'w')
        file.puts("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<project>")
        file.puts("<node name=\"localhost\" hostname=\"localhost\" clustername=\"\" datacenter=\"\" username=\"#{username}\"/>")

        nodes.each do |node|
            node = node['data']
            hostname = node['name']

            name = hostname.split('.')[0]
            sub_domain = hostname.split('.')[1..-1]
            next if not sub_domain.any?

            chef_environment = node['chef_environment']
            ip = nil
            #tags = "vip1,vip1" We'll use tags for vips belonging

            if not name =~ /^localhost$/ and not hostname =~ /^localhost\.localdomain$/
                unless node['network']['interfaces']['eth0']['addresses'].nil?
                    ip = nil
                    addresses = node['network']['interfaces']['eth0']['addresses'].to_a
                    addresses.each do |address|
                        ip = address[0] if address[1]['family'] == 'inet'
                    end
                end

                re_name = name.match(/(.*)(\d{3})(\w{3})/)

                clustername = re_name[1]
                number = re_name[2]
                datacenter = re_name[3]

                file.puts("<node name=\"#{name}\" hostname=\"#{hostname}\" clustername=\"#{clustername}\" datacenter=\"#{datacenter}\" ip=\"#{ip.to_s}\" chef_environment=\"#{chef_environment}\" username=\"#{username}\"/>")
                saved_nodes = saved_nodes +1
            end
        end

        file.puts("</project>")
        file.close unless file.nil?
        File.rename(temp_resource_file, resource_file)

        saved_nodes

    end

    private
        def escape(s)
            s && URI.escape(s.to_s)
        end
end

# main()
SCRIPT_FOLDER = File.expand_path(File.dirname(__FILE__))
RESOURCES_FILE = File.join(SCRIPT_FOLDER, "resources.xml")

NODE_ATTRIBUTES = { :name => [:name], :chef_environment => [:chef_environment], 'network' => ['network']}
QUERY_STRING = { :query => '*:*', :sort  => 'X_CHEF_id_CHEF_X asc', :start => 0, :rows  => 100000}

puts "Starting ResourcesGenerator from chef"
resources = ResourcesGenerator.new

nodes = resources.search(:node, '*.*', QUERY_STRING, NODE_ATTRIBUTES)
puts "Got #{nodes.length} nodes"

saved_nodes = resources.save(nodes, RESOURCES_FILE)
puts "Saved #{saved_nodes} nodes to file #{RESOURCES_FILE}"

exit 0
