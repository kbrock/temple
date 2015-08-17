#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__)),"..")
$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'benchmark/ips'
require 'temple'
require 'context'
require 'database_report'
# require 'erb'
#require 'byebug'

class TempleBenchmark
TEMPLATES = {
:one => %q{
%% hi
= hello
<% 3.times do |n| %>
* <%= n %>
<% end %>
},
:comments => %q{
hello
  <%# comment -- ignored -- useful in testing %>
world},
:perper => %q{
<%%
<% if true %>
  %%>
<% end %>
},
:escape => '<%= "<" %>',
:noescape => '<%== "<" %>',
:nontrim  => %q{
%% hi
= hello
<% 3.times do |n| %>
* <%= n %>
<% end %>
}
}
#    tilt_erb         = Tilt::ERBTemplate.new { @erb_code }
#    tilt_erubis      = Tilt::ErubisTemplate.new { @erb_code }
#    tilt_temple_erb  = Temple::ERB::Template.new { @erb_code }

#    bench('(2) erb')         { tilt_erb.render(context) }
#    bench('(2) erubis')      { tilt_erubis.render(context) }
#    bench('(2) temple erb')  { tilt_temple_erb.render(context) }

  def run
    ctx = Context.new
    rpt = Benchmark.ips(1,1) do |x|
      #save_bench(:key => )
      TEMPLATES.each do |name, code|
        x.report("init_#{name}") do |count|
          i = count
          while i > 0
            Temple::ERB::Template.new { code }
            i -= 1
          end
        end
    #   end
    # end
    # Benchmark.ips(1,1) do |x|
    #   TEMPLATES.each do |name, code|
        x.report("run_#{name}") do |count|
          tmpl = Temple::ERB::Template.new { code }
          i = count
          while i > 0
            tmpl.render(ctx)
            i -= 1
          end
        end
      end
    end
    # if db.modified?
      puts "exists" if db.has_metrics?
      puts "deleting #{db.sha}"
      db.delete_metrics # delete current metrics
    # end
    rpt.entries.each do |entry|
      db.add_metrics(
          entry.label,
          entry.microseconds,
          entry.iterations,
          entry.ips,
          entry.ips_sd,
          entry.measurement_cycle
      )
    end
  end

  def grouped_results
    db.results_as_hash = true
    results = db.each.map do |row|
      {
        sha: row["sha"],
        date: row["created_at"],
        label: row["label"],
        ips: row["ips"].round,
        ips_sd: row["ips_sd"].round
      }
    end
    # group first layer by sha
    g = results.group_by { |r| r[:sha] }
    # group second layer by label
    g.each { |h, hh| g[h] = hh.group_by { |hhh| hhh[:label] } }
    g
  end

  # results for line charts
  def show
    results = grouped_results
    metric_names = results[results.keys.first].keys.map { |m| m.gsub(/(init_|run_)/,'') }.uniq
    # would like to sort metric_names by ips (just for one)

    puts "var data = [{"
    results.each_with_index do |(sha, metrics), i|
      puts "  ]}, {" if i > 0
      date = metrics.first[1].first[:date] #.split("T").first
      puts "  name: \"#{sha}\", date: \"#{date}\", values: ["

      metric_names.each_with_index do |bench, j|
        metric = metrics[bench] || metrics["run_#{bench}"]
        metric = metric.first

        init_metric = metrics["init_#{bench}"]
        init_metric = init_metric.first if init_metric
        puts "," if j > 0
        print "    {bench: %-20s, ips: %-8s, sd: %-8s" %
        ["\"#{bench}\"",metric[:ips], metric[:ips_sd]]
        if init_metric
          print ", init_ips: %-8s, init_sd: %-8s" %
          [init_metric[:ips], init_metric[:ips_sd]]
        end
        print "}"
      end
      puts
    end
    puts "]}];"
  end

  def has_metrics?
    db.has_metrics?
  end

  def modified?
    db.modified?
  end

  private

  def db
    @db ||=
      begin
        dbname = File.join(File.expand_path(File.dirname(__FILE__)), "benchmark.db")
        DatabaseReport.new(dbname)
      end
  end
end

bench = TempleBenchmark.new
if !bench.has_metrics? || bench.modified? || ARGV.include?("-f")
  bench.run
end
bench.show
