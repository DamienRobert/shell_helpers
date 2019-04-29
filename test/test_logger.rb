require 'helper'
require 'shell_helpers'

describe ShellHelpers::MoreLogger do
	before do
		@buffer=StringIO.new
		@logger=SH::MoreLogger.new(@buffer)
		@logger.formatter=SH::CLILogger::BLANK_FORMAT
	end
	it "Has a color info mode" do
		@logger.cli_info "foo"
		# @buffer.string.must_equal "\e[1mfoo\e[0m\n"
		@buffer.string.must_equal "foo\n"
	end
	it "Has a color mark mode" do
		@logger.cli_mark "foo"
		@buffer.string.must_equal "\e[1mfoo\e[0m\n"
	end
	it "Has a colored important mode" do
		@logger.cli_important "foo"
		@buffer.string.must_equal "\e[34;1mfoo\e[0m\n"
	end
	it "The colored mode can add colors" do
		@logger.cli_important "foo", color: [:red]
		@buffer.string.must_equal "\e[34;1;31mfoo\e[0m\n"
	end
	it "Has an important mode" do
		@logger.important "foo"
		@buffer.string.must_equal "foo\n"
	end
	it "Can give a numeric level" do
		@logger.cli_add(@logger.severity(:important), "foo")
		@buffer.string.must_equal "foo\n"
	end
	it "Default to debug level" do
		@logger.debug("foo")
		@buffer.string.must_equal "foo\n"
	end
	it "Don't show below debug level" do
		@logger.debug3("foo")
		@buffer.string.must_equal ""
	end
	it "Can change level" do
		old_level=@logger.level
		@logger.level=:debug3
		@logger.debug3("foo")
		@logger.level=old_level
		@buffer.string.must_equal "foo\n"
	end
end
