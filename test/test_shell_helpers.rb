require 'helper'
require 'shell_helpers'

class TestShellHelpers < Minitest::Test

  def test_version
    version = ShellHelpers.const_get('VERSION')

    assert(!version.empty?, 'should have a VERSION constant')
  end

end
