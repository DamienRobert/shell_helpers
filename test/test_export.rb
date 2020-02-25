require 'helper'
require 'shell_helpers'

describe SH::Export do
	it "can export a value" do
		_(SH.export_value("foo")).must_equal "foo"
		_(SH.export_value(["foo","bar"])).must_equal "(foo bar)"
		_(SH.export_value(["foo","bar"])).must_equal "(foo bar)"
		_(SH.export_value(Set.new(["foo","bar"]))).must_equal "(foo bar)"
		_(SH.export_value({foo:"bar"})).must_equal "(foo bar)"
	end

	it "can escape a shell name" do
		#foo/bar get interpreted as FOO_BAR
		_(SH.escape_name("foo/bar")).must_equal("FOO_BAR")
		_(SH.escape_name("foo",prefix:"ploum",upcase:false)).must_equal("ploumfoo")
	end

	it "can export a variable" do
		_(SH.export_variable("foo","baz")).must_equal "FOO=baz\n"
		_(SH.export_variable("foo","baz",local:true,export:true)).must_equal "local FOO\nFOO=baz\nexport FOO\n"
		_(SH.export_variable("foo",{bar:"baz"})).must_equal "typeset -A FOO\nFOO=(bar baz)\n"
	end

	it "can export a hash" do
		_(SH.export_variables({foo:"bar",ploum:"plam"})).must_equal "FOO=bar\nPLOUM=plam\n"
	end

	it "can select which keys to export" do
		h={ploum: "plam", foo: {a: 1, b:2}}
		_(SH.export_parse(h,"ploum")).must_equal "PLOUM=plam\n"
		_(SH.export_parse(h,:ploum)).must_equal "PLOUM=plam\n"
		#can select a hash in a hash
		_(SH.export_parse(h,"foo/a")).must_equal "FOO_A=1\n"
		#can export severable variables
		_(SH.export_parse(h,"ploum,foo/a")).must_equal "PLOUM=plam\nFOO_A=1\n"
		#can name the variables
		_(SH.export_parse(h,"var:ploum")).must_equal "VAR=plam\n"
		_(SH.export_parse(h,"var2:foo/a")).must_equal "VAR2=1\n"
		_(SH.export_parse(h,"var:ploum,foo/a")).must_equal "VAR=plam\nFOO_A=1\n"
		#can export values by ending with /
		_(SH.export_parse(h,"foo/")).must_equal "A=1\nB=2\n"
		#can select a prefix for the values
		_(SH.export_parse(h,"prefix_:foo/")).must_equal "prefix_A=1\nprefix_B=2\n"
		#use '/' to select the whole hash
		_(SH.export_parse(h,"/")).must_equal "typeset -A ALL\nALL=(ploum plam foo \\{:a\\=\\>1,\\ :b\\=\\>2\\})\n"
		#use '//' to export values in the whole hash
		_(SH.export_parse(h,"//")).must_equal "PLOUM=plam\ntypeset -A FOO\nFOO=(a 1 b 2)\n"
		_(SH.export_parse(h,"prefix_://")).must_equal "prefix_PLOUM=plam\ntypeset -A prefix_FOO\nprefix_FOO=(a 1 b 2)\n"
		#can have options
		_(SH.export_parse(h,"ploum!local!export")).must_equal "local PLOUM\nPLOUM=plam\nexport PLOUM\n"
		#use !! for global options
		_(SH.export_parse(h,"ploum!local,var:foo/a!!export")).must_equal "local PLOUM\nPLOUM=plam\nexport PLOUM\nVAR=1\nexport VAR\n"
	end

	it "can import a value" do
		_(SH.import_value("foo")).must_equal "foo"
		_(SH.import_value("foo", type: Symbol)).must_equal :foo
		_(SH.import_value("(foo bar)", type: Array)).must_equal %w(foo bar)
		_(SH.import_value("(foo bar)", type: Hash)).must_equal({"foo"=>"bar"})
	end

	it "can import a variable" do
		_(SH.import_variable("foo=bar")).must_equal ["foo","bar"]
		_(SH.import_variable("foo='bar'")).must_equal ["foo","bar"]
		_(SH.import_variable("foo=(bar baz)")).must_equal ["foo",%w(bar baz)]
	end

	it "can import instructions" do
		_(SH.import_parse("foo=bar,ploum=plim")).must_equal({foo: "bar", ploum: "plim"})
		_(SH.import_parse(<<EOS)).must_equal({foo: "bar", ploum: %w(plim plam)})
foo=bar
ploum=(plim plam)
EOS
		_(SH.import_parse("foo/bar=baz,ploum=plim")).must_equal({foo: {bar: "baz"}, ploum: "plim"})
	end
end
