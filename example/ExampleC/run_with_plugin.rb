#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true

require 'cocoapods'
require 'cocoapods-podgenerate'

Pod::PodGenerate.activate

ENV['COCOAPODS_PODGENERATE_DEBUG'] = '1' if ARGV.include?('--debug')

config = Pod::Config.instance
config.verbose = ARGV.include?('--verbose')

Pod::UI.puts '[cocoapods-podgenerate] PodGenerate plugin active (production mode)'

installer = Pod::Installer.new(config.sandbox, config.podfile, config.lockfile)
installer.install!
