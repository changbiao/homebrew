require 'cmd/install'

class Fixnum
  def plural_s
    if self > 1 then "s" else "" end
  end
end

module Homebrew extend self
  def upgrade
    if Process.uid.zero? and not File.stat(HOMEBREW_BREW_FILE).uid.zero?
      # note we only abort if Homebrew is *not* installed as sudo and the user
      # calls brew as root. The fix is to chown brew to root.
      abort "Cowardly refusing to `sudo brew upgrade'"
    end

    Homebrew.perform_preinstall_checks

    if ARGV.named.empty?
      require 'cmd/outdated'
      outdated = Homebrew.outdated_brews
    else
      outdated = ARGV.formulae.select do |f|
        if f.installed?
          onoe "#{f}-#{f.installed_version} already installed"
        elsif not f.rack.directory? or f.rack.subdirs.empty?
          onoe "#{f} not installed"
        else
          true
        end
      end
      exit 1 if outdated.empty?
    end

    unless upgrade_pinned?
      pinned = outdated.select(&:pinned?)
      outdated -= pinned
    end

    if outdated.length > 0
      oh1 "Upgrading #{outdated.length} outdated package#{outdated.length.plural_s}, with result:"
      puts outdated.map{ |f| "#{f.name} #{f.version}" } * ", "
    end

    if not upgrade_pinned? and pinned.length > 0
      oh1 "Not upgrading #{pinned.length} pinned package#{pinned.length.plural_s}:"
      puts pinned.map{ |f| "#{f.name} #{f.version}" } * ", "
    end

    outdated.each { |f| upgrade_formula(f) }
  end

  def upgrade_pinned?
    not ARGV.named.empty?
  end

  def upgrade_formula f
    tab = Tab.for_formula(f)

    # Inject options from a previous install into the formula's
    # BuildOptions object. TODO clean this up.
    f.build.args += tab.used_options

    outdated_keg = Keg.new(f.linked_keg.realpath) rescue nil

    installer = FormulaInstaller.new(f)
    installer.tab = tab
    installer.show_header = false

    oh1 "Upgrading #{f.name}"

    # first we unlink the currently active keg for this formula otherwise it is
    # possible for the existing build to interfere with the build we are about to
    # do! Seriously, it happens!
    outdated_keg.unlink if outdated_keg

    installer.install
    installer.caveats
    installer.finish

    # If the formula was pinned, and we were force-upgrading it, unpin and
    # pin it again to get a symlink pointing to the correct keg.
    if f.pinned?
      f.unpin
      f.pin
    end
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to upgrade f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e
  rescue BuildError => e
    e.dump
    puts
    Homebrew.failed = true
  ensure
    # restore previous installation state if build failed
    outdated_keg.link if outdated_keg and not f.installed? rescue nil
  end

end
