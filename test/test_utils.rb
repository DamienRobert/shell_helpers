require 'helper'
require 'shell_helpers'

describe SH::ShellExport do
	it "can export a value" do
		SH.export_value("foo").must_equal "foo"
		SH.export_value(["foo","bar"]).must_equal "(foo bar)"
		SH.export_value(["foo","bar"]).must_equal "(foo bar)"
		SH.export_value(Set.new(["foo","bar"])).must_equal "(foo bar)"
		SH.export_value({foo:"bar"}).must_equal "(foo bar)"
	end

	it "can escape a shell name" do
		#foo/bar get interpreted as FOO_BAR
		SH.escape_name("foo/bar").must_equal("FOO_BAR")
		SH.escape_name("foo",prefix:"ploum",upcase:false).must_equal("ploumfoo")
	end

	it "can export a variable" do
		SH.export_variable("foo","baz").must_equal "FOO=baz\n"
		SH.export_variable("foo","baz",local:true,export:true).must_equal "local FOO\nFOO=baz\nexport FOO\n"
		SH.export_variable("foo",{bar:"baz"}).must_equal "typeset -A FOO\nFOO=(bar baz)\n"
	end

	it "can export a hash" do
		SH.export_variables({foo:"bar",ploum:"plam"}).must_equal "FOO=bar\nPLOUM=plam\n"
	end

	it "can select which keys to export" do
		h={ploum: "plam", foo: {a: 1, b:2}}
		SH.export_parse(h,"ploum").must_equal "PLOUM=plam\n"
		SH.export_parse(h,:ploum).must_equal "PLOUM=plam\n"
		#can select a hash in a hash
		SH.export_parse(h,"foo/a").must_equal "FOO_A=1\n"
		#can export severable variables
		SH.export_parse(h,"ploum,foo/a").must_equal "PLOUM=plam\nFOO_A=1\n"
		#can name the variables
		SH.export_parse(h,"var:ploum").must_equal "VAR=plam\n"
		SH.export_parse(h,"var2:foo/a").must_equal "VAR2=1\n"
		SH.export_parse(h,"var:ploum,foo/a").must_equal "VAR=plam\nFOO_A=1\n"
		#can export values by ending with /
		SH.export_parse(h,"foo/").must_equal "A=1\nB=2\n"
		#can select a prefix for the values
		SH.export_parse(h,"prefix_:foo/").must_equal "prefix_A=1\nprefix_B=2\n"
		#use '/' to select the whole hash
		SH.export_parse(h,"/").must_equal "typeset -A ALL\nALL=(ploum plam foo \\{:a\\=\\>1,\\ :b\\=\\>2\\})\n"
		#use '//' to export values in the whole hash
		SH.export_parse(h,"//").must_equal "PLOUM=plam\ntypeset -A FOO\nFOO=(a 1 b 2)\n"
		SH.export_parse(h,"prefix_://").must_equal "prefix_PLOUM=plam\ntypeset -A prefix_FOO\nprefix_FOO=(a 1 b 2)\n"
		#can have options
		SH.export_parse(h,"ploum!local!export").must_equal "local PLOUM\nPLOUM=plam\nexport PLOUM\n"
		#use !! for global options
		SH.export_parse(h,"ploum!local,var:foo/a!!export").must_equal "local PLOUM\nPLOUM=plam\nexport PLOUM\nVAR=1\nexport VAR\n"
	end
end
