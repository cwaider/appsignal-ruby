describe Appsignal::SampleData do
  let(:data) { described_class.new }

  describe "#set" do
    it "returns the set value" do
      data.set(:key1 => "value 1")

      expect(data.value).to eq(:key1 => "value 1")
    end

    it "returns the set value from the block" do
      data.set { { :key1 => "value 1" } }

      expect(data.value).to eq(:key1 => "value 1")
    end

    it "overwrites any existing value" do
      data.set(:key1 => "value 1")
      data.set(:key2 => "value 2")

      expect(data.value).to eq(:key2 => "value 2")
    end

    it "overwrites any previously add-ed value" do
      data.add(:key1 => "value 1")
      data.set(:key2 => "value 2")

      expect(data.value).to eq(:key2 => "value 2")
    end

    it "overwrites any existing value with the block being leading" do
      data.set(:key1 => "value 1") { { :key2 => "value 2" } }

      expect(data.value).to eq(:key2 => "value 2")
    end

    it "overwrites any existing value with the last set value being leading" do
      data.set(:key1 => "value 1")
      data.set { { :key2 => "value 2" } }
      data.set(:key3 => "value 3")

      expect(data.value).to eq(:key3 => "value 3")
    end

    it "ignores invalid values" do
      data.set("string")
      expect(data.value).to be_nil

      set = Set.new
      set.add("abc")
      data.set(set)
      expect(data.value).to be_nil

      instance = Class.new
      data.set(instance)
      expect(data.value).to be_nil
    end
  end

  describe "#add" do
    it "returns the set value" do
      data.add(:key1 => "value 1")

      expect(data.value).to eq(:key1 => "value 1")
    end

    it "adds the value with the block being leading" do
      data.add(:key1 => "value 1") { { :key2 => "value 2" } }

      expect(data.value).to eq(:key2 => "value 2")
    end

    it "merges multiple values" do
      data.add(:key1 => "value 1")
      data.add(:key2 => "value 2")

      expect(data.value).to eq(:key1 => "value 1", :key2 => "value 2")
    end

    it "merges all values" do
      data.add(:key1 => "value 1")
      data.add { { :key2 => "value 2" } }
      data.add(:key3 => "value 3")

      expect(data.value).to eq(:key1 => "value 1", :key2 => "value 2", :key3 => "value 3")
    end

    it "merges all array values" do
      data.add([:first_arg])
      data.add { [:from_block] }
      data.add([:second_arg])

      expect(data.value).to eq([:first_arg, :from_block, :second_arg])
    end

    it "overwrites a different value type" do
      data.add(:key1 => "value 1")
      expect(data.value).to eq(:key1 => "value 1")

      data.add(["abc"])
      expect(data.value).to eq(["abc"])
    end

    it "ignores invalid values" do
      data.add("string")
      expect(data.value).to be_nil

      set = Set.new
      set.add("abc")
      data.add(set)
      expect(data.value).to be_nil

      instance = Class.new
      data.add(instance)
      expect(data.value).to be_nil
    end
  end

  describe "#value?" do
    it "returns true when value is set" do
      data.set(["abc"])
      expect(data.value?).to be_truthy
    end

    it "returns true when value is set with a block" do
      data.set { ["abc"] }
      expect(data.value?).to be_truthy
    end

    it "returns false when the value is not set" do
      expect(data.value?).to be_falsey
    end
  end
end
