require 'active_support/all'

RSpec.describe Rapidity::Share::Base do
  let(:namespace){ "test_workplace" }
  let(:pool) do
    ConnectionPool.new(size: 10) do
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))
    end
  end
  let(:producer){ Rapidity::Share::Producer.new(pool) }
  subject(:base){ described_class.new(pool) }

  before(:each) do
    pool.with { |r| r.flushdb }
  end

  context "Class level script cache" do

    before :all do
      # reset cache for all classes THROUGH instance
      [Rapidity::Share::Base, Rapidity::Share::Sender, Rapidity::Share::Producer].each do |klass|
        klass.new(nil).send(:reset_lua_scripts)
      end
    end

    [Rapidity::Share::Base, Rapidity::Share::Sender, Rapidity::Share::Producer].each do |klass|
      describe klass do
        subject(:instance){ klass.new(pool) }
        let(:scripts) { klass::BASE_SCRIPTS + klass::LUA_SCRIPTS }

        before :all do
          # reset cache for class THROUGH instance
          klass.new(nil).send(:reset_lua_scripts)
        end

        def scripts_to_h(klass_or_instance, names)
          names.each_with_object({}) do |s, ret|
            ret["@lua_#{s}"] = klass_or_instance.instance_variable_get("@lua_#{s}")
          end.compact
        end

        # Очерёдность этих тестов имеет значение
        # 1. Проверка что в instance и class cache ничего нету
        it {
          expect(scripts_to_h(klass, scripts)).to be_empty
          expect(scripts_to_h(instance, scripts)).to be_empty
          expect{instance.send(:restore_lua_hashes)}.not_to change{scripts_to_h(klass, scripts)}
        }
        # Очерёдность этих тестов имеет значение
        # 2. Проверка что load_redis_scripts обновляет cache
        it {
          expect(scripts_to_h(klass, scripts)).to be_empty
          expect(scripts_to_h(instance, scripts)).to be_empty
          expect{instance.send(:load_redis_scripts)}.to change{scripts_to_h(klass, scripts)}
        }
        # Очерёдность этих тестов имеет значение
        # 3. Проверка что скрипты уже есть в cache и сразу берутся оттуда
        it {
          expect(scripts_to_h(klass, scripts)).not_to be_empty
          expect(scripts_to_h(instance, scripts)).not_to be_empty
          expect{instance.send(:restore_lua_hashes)}.not_to change{scripts_to_h(klass, scripts)}
        }

      end
    end
  end

  context "#noscript" do
    it 'reload scripts' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace)
      producer.init(limit)
      result = base.info(limit)
      expect(result.success).to eq(true)

      pool.with do |conn|
        conn.with do |r|
          r.script(:flush, 'SYNC')
        end
      end

      result = base.info(limit)
      expect(result.success).to eq(true)
    end

    it 'reload scripts not not exceed max attempts' do
      limit = Rapidity::Share::Limit.new('limit_1', 20, 100, namespace: namespace)
      producer.init(limit)
      result = base.info(limit)
      expect(result.success).to eq(true)

      expect do
        base.wrap_executed_script do |r|
          pool.with do |conn|
            conn.with do |r|
              r.script(:flush, 'SYNC')
              r.evalsha(base.instance_variable_get('@lua_info'), keys: ['42'])
            end
          end
        end
      end.to raise_error(Redis::CommandError)
    end
  end
end