== Release v0.7.1 (2020-02-26) ==

	* logger.rb: use class_eval
	* Add .bundle/config
	* Bump require gem versions
	* Add github action for tests
	* Fix minitest warning
	* Fix warnings

== Release v0.7.0 (2020-02-19) ==

	* Bump version and update ChangeLog.md
	* Copyright
	* rsync: Use -zz instead of -z (--new-compress)
	* Fixes for ruby 2.7
	* rsync: add clobber option
	* logger: fix logger.debug {"foo"}
	* sysutils.rb: add exemples
	* Misc bug fixes and doc
	* sh.rb: correct examples
	* Pathname.read!
	* pathname: old_glob -> rel_glob
	* pathname: deprecate glob, it is now a builtin
	* logger: fix output showing twice
	* Bug fix
	* Fix tests
	* Small tweaks
	* logger2.rb is now logger.rb
	* logger2: bug fixes
	* logger2.rb: continue merge
	* logger2: Merge MoreLogger and ColorLogger
	* Rework MoreLogger
	* SH: log_options (for OptParse)
	* Fix tests
	* logger.rb: new class ColorLogger
	* logger: cli_info -> not bold
	* Logger: cli_methods configuration
	* logger: small tweaks
	* tests for logger
	* Logger: cli_*
	* Update Rakefile
	* Update Rakefile
	* logger.rb: add bold
	* logger: color_add
	* severity: debug1=debug and verbose1=verbose
	* logger: verbose* levels
	* Logger#cli_level: helper to set up log level
	* logger: debug1, debug2, debug3
	* run.rb: bug fixes
	* Bug fixes
	* SH.log
	* Sh: use instance_method for run_sudo_loop
	* pathname: add missing require
	* ssh: ssh_env option to pass env to the remote
	* Run#run_success
	* SH.sh: by default only return success
	* Sh.sh: specify argv0
	* Sh.sh: accept a block
	* Sh: sudo_loop
	* Sh#sh_or_proc
	* Bug fixes

== Release v0.6.0 (2018-09-07) ==

	* Bump version to 0.6.0

== Release v0.3.0 (2018-09-07) ==

	* Bump version
	* run+sh: unify command handling
	* logger.rb: add quiet
	* SH.sh: sudo can be a complex command
	* Bug fixes + better logging for sh
	* ShConfig + VirtualFile
	* ShConfig: remove context
	* ShConfig: wrap
	* Sh: ShConfig
	* Excpetions: subclass StandardError
	* Run: bug fix
	* Run.run: add :quiet alias for error: :quiet
	* Run.run: replace status_mode by error_mode to be clearer
	* run: accept environments, wrap into ProcessStatus if needed
	* run.rb: run_simple now calls run
	* sysutils: small improvements
	* Sysutils: partition_infos + bug fixes
	* Pathname#readbin
	* SH.sh: detach vs spawn
	* ssh: use URI::Ssh to be more lenient for host name
	* Rsync exclude: escape
	* Clean up
	* Rsync: exclude
	* utils: refactor
	* rsync: add sshcommand option
	* ssh: :sshkit and :net_ssh modes
	* Pathname: add logging
	* SH.sh: allow mode to be :exec too
	* Utils.ssh: more mode, and split ssh_command
	* Utils.ssh: user
	* Utils.ssh:
	* sysutils: bug fix
	* Pathname#glob: expand to pathname
	* Pathname#rel_path_to: convert the target to a Pathname
	* sysutils: allows mountoptions to be a String
	* Remove LogHelper
	* sh.rb: change execute log level to be :info
	* Utils: eval_shell
	* Bug fix
	* Bug fix
	* make_dir_or_subvolume
	* sysutils: stat_files
	* sysutils: bug fixes
	* sysutils: check devices for name too
	* sysutils: block handling to automatically unmount
	* sysutils: use Pathname#<=>
	* run/sh: add a 'sudo' option
	* sysutils: improve find_devices
	* sysutils: fs_infos return a hash rather than an array
	* sysutils: unify keywords for blkid, lsblk, findmnt
	* sysutils: lsblk and findmnt
	* sysutils: partition types
	* sysutils: commands for sysadmins
	* pathname: chown
	* rsync: more convenient options passing
	* Copyright
	* rsync: correct a typo
	* Wrap chdir
	* SH::Sh: Add DryRun module
	* Pathname: misc utils functions
	* Sh.sh: correctly handle false options
	* docs typos
	* Sh: activates logging by default
	* sh_commands: chomp newline

== Release v0.2.0 (2018-02-01) ==

	* Bump versions
	* rsync: add chown option
	* Pathname#{text?,binary?}: return false on a directory
	* run.rb: improve api
	* Import changes from methadone
	* binary?: Encoding to ascii would lose to many bits
	* Pathname#text? Don't invoke 'file'
	* Pathname#text?, Pathname#glob
	* run_lazy: simplify the implementation
	* run: add run_enum
	* run_pager: can pass arguments to the pager
	* Be explicit about require
	* Add missing options lib
	* Fix require
	* Split utils.rb into utils.rb and export.rb
	* Pathname#hidden? was defined twice
	* Add badges
	* In travis the test should be under 'bundle exec'
	* We need the git version of drain for now
	* Update gemspec
	* Add rake dependency
	* Configure travis and streamline rake and test files
	* rsync: using relative we usually want no-implied-dirs
	* utils: more rsync options
	* import_parse: inline mode
	* utils: add capture_stdout
	* shrun: helper to run system/spawn with the correct options
	* sh: Pass along options
	* logger: progname should affect the error logger too
	* SH.sh: allow to detach
	* bugfix
	* Unquote value
	* utils.rb: put import_parse in the correct Module
	* import_variable: match variable name on \S*
	* test import_parse
	* Import variables
	* Copyright
	* export_value: test if the object respond to :to_a or :to_h
	* test: test_utils.rb (only ShellExport for now)
	* Fixes for ruby 2.4
	* find: handle max_depth
	* utils: when exporting a group/name variable replace '/' with '_'
	* Copyright
	* Add examples
	* Pathname.cd
	* find_files
	* find_file
	* RunSimple: add error: nil
	* Add pathname#split_all
	* Pathname: add may_exist?
	* Pathname: add chattr
	* More documentation on SH.find
	* FileUtils#chmod requires the mode as first parameter
	* rsync: the option is --suffix, not --backup-suffix
	* rsync: Add expected: 23
	* rsync: add option to clean output directory
	* rsync: add :delete option
	* Add rsync helper
	* Rename Sh#commands to Sh#sh_commands
	* Add Sh.commands
	* Add Pathname#copy_entry
	* rmtree should be an alias to rm_rf
	* Add backup mode to filewrite, and mkpath mode ton on_*
	* Add rsync helper
	* Pathname#squel_dir: allow to pass mkpath
	* SH.find now accept a :prune options
	* We should check if CLILogging has @@logger, not Module
	* Move options.rb to another library
	* mv_and_ln.rb: dereference
	* mv_and_ln: options tweaks
	* Add mv_and_ln.rb
	* Pathname: use convert_path in rel_path_to
	* Handle relative_path_from errors
	* Add new mode to not dereference symlink in some actions
	* abs_to_rel.rb
	* A binary using the features of pathname
	* Inner scope
	* Add helper functions
	* find: add a depth first option
	* find: rename depth to max_depth
	* Pathname#squel_dir: we need to use squel inside the find
	* Bugfixes in Pathname and ShUtils.find
	* Pathname#squel_dir
	* Start working on Pathname#squel
	* Pathname: add rel_path_from
	* Use included hooks
	* Put pathname functionality into Modules and Classes
	* Correct constant reference
	* Pathname: fix aliases
	* SH::Pathname: put changes in module so that other class can use them
	* Merge branch 'master-imb'
	* Small bug fixes
	* SH.find: any filter should prevent the yield
	* Pathname: factorize the new name usual method
	* Pathname: new_name
	* Implement SH::Pathname#follow
	* Add Pathname#rel_path
	* Readme: Add warning
	* pathname.rb: raise some Errors if needed
	* Implement a 'magic' rm function
	* Pathname: use FileUtils when possible
	* Add a module LogHelper to help setup logging
	* Add a fallback if SimpleColor is not found
	* Some files/names have changed
	* Rename SH to ShellHelpers

== Release v0.1.0 (2015-02-24) ==

	* Add dependency
	* Description
	* Add library
	* Initial commit.

