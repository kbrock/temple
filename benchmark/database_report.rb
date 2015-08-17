require "sqlite3"
require "date"

class DatabaseReport
  include Enumerable

  # this is for tests - get out of here
  attr_reader :filename
  # default sha for inserts
  attr_writer :sha
  # length to trim the sha (default: 8)
  attr_accessor :sha_length
  # date of current metrics
  attr_accessor :now

  def initialize(filename)
    @filename = filename
    @sha_length = 8
  end

  # Add metrics to the database
  # equivalent to Benchmark::IPS::Report::Entry.
  # @param [#to_s] label Label of entry.
  # @param [Integer] us Measured time in microsecond.
  # @param [Integer] iters Iterations.
  # @param [Float] ips Iterations per second.
  # @param [Float] ips_sd Standard deviation of iterations per second.
  # @param [Integer] cycles Number of Cycles.
  def add_metrics(label, us, iters, ips, ips_sd, cycles)
    insert.execute sha, now, label, us, iters, ips, ips_sd, cycles
  end

  # def [](key)
  #   db.execute("select ips, stddev from metrics where sha = ? and name = ?", sha, key).map { |row| row.first }.first
  # end

  # def include?(key)
  #   !!self[key]
  # end

  def results_as_hash=(value)
    db.results_as_hash = value
  end

  def each(&block)
    # order by rowid
    db.execute "select * from metrics order by created_at, label", &block
  end

  def others(&block)
    db.execute "select * from metrics where sha != ? order by created_at, label", sha, &block
  end

  def delete_metrics(sha1 = sha)
    db.execute "delete from metrics where sha = ?", sha1
  end

  def has_metrics?(sha1 = sha)
    db.execute "select 1 from metrics where sha = ?", sha1 do |row|
      return true
    end
    return false
  end

  # git
  def sha
    @sha ||= modified? ? 'current' : calc_sha[0...@sha_length]
  end

  def now
    @now ||= modified? ? DateTime.now.to_s : calc_date
  end

  # use unstaged? or changed? based upon your needs
  def modified?
    refresh_index || changed? || unstaged?
  end

  def calc_sha
    `git show-ref --head --hash head`.chomp
  end

  def calc_date
    `git log -1 --format=%cd --date=iso-strict`.chomp
  end

  # @return [Boolean] false saying nothing has changed
  def refresh_index
    `git update-index -q --ignore-submodules --refresh`
    false
  end

  # @return [Boolean] true if unstaged files exist
  def unstaged?
    `git diff-files --quiet --ignore-submodules --`
    !$?.success?
  end

  # @return [Boolean] true if files are changed
  def changed?
    `git diff-index --cached --quiet HEAD --ignore-submodules --`
    !$?.success?
  end

  private

  def db
    @db ||= create
  end

  def insert
    @insert ||= db.prepare "insert into metrics (sha, created_at, label, microseconds, iterations, ips, ips_sd, cycles) values (?, ?, ?, ?, ?, ?, ?, ?)"
  end

  def create
    SQLite3::Database.new(filename).tap do |db|
      db.execute("create table if not exists metrics ( " +
        "sha text, created_at datetime, label text, microseconds integer, iterations integer, "+
        "ips float, ips_sd float, cycles integer)")
    end
  end
end
