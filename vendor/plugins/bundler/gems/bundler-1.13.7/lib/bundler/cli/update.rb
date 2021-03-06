# frozen_string_literal: true
module Bundler
  class CLI::Update
    attr_reader :options, :gems
    def initialize(options, gems)
      @options = options
      @gems = gems
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.settings[:plugins]

      sources = Array(options[:source])
      groups  = Array(options[:group]).map(&:to_sym)

      if gems.empty? && sources.empty? && groups.empty? && !options[:ruby] && !options[:bundler]
        # We're doing a full update
        Bundler.definition(true)
      else
        unless Bundler.default_lockfile.exist?
          raise GemfileLockNotFound, "This Bundle hasn't been installed yet. " \
            "Run `bundle install` to update and install the bundled gems."
        end
        # cycle through the requested gems, to make sure they exist
        names = Bundler.locked_gems.specs.map(&:name)
        gems.each do |g|
          next if names.include?(g)
          require "bundler/cli/common"
          raise GemNotFound, Bundler::CLI::Common.gem_not_found_message(g, names)
        end

        if groups.any?
          specs = Bundler.definition.specs_for groups
          gems.concat(specs.map(&:name))
        end

        Bundler.definition(:gems => gems, :sources => sources, :ruby => options[:ruby])
      end

      patch_level = [:major, :minor, :patch].select {|v| options.keys.include?(v.to_s) }
      raise ProductionError, "Provide only one of the following options: #{patch_level.join(", ")}" unless patch_level.length <= 1
      Bundler.definition.gem_version_promoter.tap do |gvp|
        gvp.level = patch_level.first || :major
        gvp.strict = options[:strict]
      end

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      opts = options.dup
      opts["update"] = true
      opts["local"] = options[:local]

      Bundler.settings[:jobs] = opts["jobs"] if opts["jobs"]

      # rubygems plugins sometimes hook into the gem install process
      Gem.load_env_plugins if Gem.respond_to?(:load_env_plugins)

      Bundler.definition.validate_ruby!
      Installer.install Bundler.root, Bundler.definition, opts
      Bundler.load.cache if Bundler.app_cache.exist?

      if Bundler.settings[:clean] && Bundler.settings[:path]
        require "bundler/cli/clean"
        Bundler::CLI::Clean.new(options).run
      end

      Bundler.ui.confirm "Bundle updated!"
      without_groups_messages
    end

  private

    def without_groups_messages
      return unless Bundler.settings.without.any?
      require "bundler/cli/common"
      Bundler.ui.confirm Bundler::CLI::Common.without_groups_message
    end
  end
end
