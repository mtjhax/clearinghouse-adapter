class Hash
  # Better deep_dup'ing of nested hashes. Since we're only working with
  # simple attribute hashes, Marshal should work fine
  def deep_dup
    Marshal.load(Marshal.dump(self))
  end
end