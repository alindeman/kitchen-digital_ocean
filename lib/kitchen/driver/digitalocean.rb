# -*- encoding: utf-8 -*-
#
# Author:: Greg Fitzgerald (<greg@gregf.org>)
#
# Copyright (C) 2013, Greg Fitzgerald
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'benchmark'
require 'fog'
require 'kitchen'
require 'etc'
require 'socket'

module Kitchen
  module Driver
    # Digital Ocean driver for Kitchen.
    #
    # @author Greg Fitzgerald <greg@gregf.org>
    class Digitalocean < Kitchen::Driver::SSHBase
      default_config :username, 'root'
      default_config :port, '22'

      default_config :private_networking do
        true
      end

      default_config :region_id do |driver|
        driver.default_region
      end

      default_config :flavor_id do |driver|
        driver.default_flavor
      end

      default_config :image_id do |driver|
        driver.default_image
      end

      default_config :server_name do |driver|
        driver.default_name
      end

      default_config :digitalocean_client_id do
        ENV['DIGITALOCEAN_CLIENT_ID']
      end

      default_config :digitalocean_api_key do
        ENV['DIGITALOCEAN_API_KEY']
      end

      default_config :ssh_key_ids do
        ENV['DIGITALOCEAN_SSH_KEY_IDS'] || ENV['SSH_KEY_IDS']
      end

      required_config :digitalocean_client_id
      required_config :digitalocean_api_key
      required_config :ssh_key_ids
      required_config :image_id
      required_config :flavor_id
      required_config :region_id

      def create(state)
        server = create_server
        state[:server_id] = server.id

        info("Digital Ocean instance <#{state[:server_id]}> created.")
        server.wait_for { print '.'; ready? } ; print '(server ready)'
        state[:hostname] = server.public_ip_address
        wait_for_sshd(state[:hostname]) ; print "(ssh ready)\n"
        debug("digitalocean:create #{state[:hostname]}")
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:server_id].nil?

        server = compute.servers.get(state[:server_id])
        server.destroy unless server.nil?
        info("Digital Ocean instance <#{state[:server_id]}> destroyed.")
        state.delete(:server_id)
        state.delete(:hostname)
      end

      def default_flavor
        defined_flavor = config.fetch(:flavor) { '512mb' }
        begin
          flavor = compute.flavors
            .find { |i| i.name.match(/#{defined_flavor}/i) }
          flavor.id
        rescue NoMethodError
          raise ActionFailed,
                "Could not find a match for the flavor #{defined_flavor}"
        end
      end

      def default_region
        defined_region = config.fetch(:region) { 'New York 2' }
        begin
          region = compute.regions
            .find { |i| i.name.match(/#{defined_region}/i) }
          region.id
        rescue NoMethodError
          raise ActionFailed,
                "Could not find a match for the region #{defined_region}"
        end
      end

      def default_image
        name = instance.platform.name.to_s.gsub(/(-|_)/, ' ')
        defined_image = config.fetch(:image) { name }
        begin
          image = compute.images.find { |i| i.name.match(/#{defined_image}/i) }
          image.id
        rescue NoMethodError
          raise ActionFailed,
                "Could not find a match for the image #{defined_image}"
        end
      end

      def default_name
        # Generate what should be a unique server name
        rand_str = Array.new(8) { rand(36).to_s(36) }.join
        "#{instance.name}-"\
        "#{Etc.getlogin.gsub('_', '-')}-"\
        "#{rand_str}-"\
        "#{Socket.gethostname}"
      end

      private

      def compute
        debug_compute_config

        server_def = {
          provider:               'Digitalocean',
          digitalocean_api_key:   config[:digitalocean_api_key],
          digitalocean_client_id: config[:digitalocean_client_id]
        }

        Fog::Compute.new(server_def)
      end

      def create_server
        debug_server_config

        compute.servers.create(
          name:               config[:server_name],
          image_id:           config[:image_id],
          flavor_id:          config[:flavor_id],
          region_id:          config[:region_id],
          ssh_key_ids:        config[:ssh_key_ids],
          private_networking: config[:private_networking]
        )
      end

      def debug_server_config
        debug("digitalocean:name #{config[:server_name]}")
        debug("digitalocean:image_id #{config[:image_id]}")
        debug("digitalocean:flavor_id #{config[:flavor_id]}")
        debug("digitalocean:region_id #{config[:region_id]}")
        debug("digitalocean:ssh_key_ids #{config[:ssh_key_ids]}")
        debug("digitalocean:private_networking #{config[:private_networking]}")
      end

      def debug_compute_config
        debug("digitalocean_api_key #{config[:digitalocean_api_key]}")
        debug("digitalocean_client_id #{config[:digitalocean_client_id]}")
      end
    end
  end
end
