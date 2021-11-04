# frozen_string_literal: true

require_relative './helpers'
require 'sqlite3'
require 'active_record'

RSpec.describe Oso::Oso do # rubocop:disable Metrics/BlockLength
  D = Oso::Polar::Data
  Join = D::ArelJoin
  Src = D::ArelSource
  Select = D::ArelSelect
  Field = D::Proj
  Value = D::Value
  context 'new filters' do
    persons = Src[Person]
    signs = Src[Sign]
    person_name = Field[persons, :name]
    person_sign_name = Field[persons, :sign_name]
    sign_name = Field[signs, :name]
    persons_signs = Join[persons, person_sign_name, sign_name, signs]
    context 'astrology' do
      it 'field value no join' do
        # person.name = 'eden'
        result = Select[persons, person_name, Value['eden']].to_a
        expect(result).to eq [eden]

        # person.name != 'eden'
        result = Select[persons, person_name, Value['eden'], kind: :neq].to_a
        expect(result.length).to be 11
        expect(result).not_to include eden
      end

      it 'field value one join' do
        # person.sign.name = 'cancer'
        result = Select[persons_signs, sign_name, Value['cancer']].to_a
        expect(result).to eq [eden]
        # person.sign.name != 'cancer'
        result = Select[persons_signs, sign_name, Value['cancer'], kind: :neq].to_a
        expect(result.length).to be 11
        expect(result).not_to include eden
      end

      it 'field field one join' do
        # person.name = person.sign.name
        result = Select[persons_signs, person_name, sign_name].to_a
        expect(result).to eq [leo]

        # person.name != person.sign.name
        result = Select[persons_signs, person_name, sign_name, kind: :neq].to_a
        expect(result.length).to be 11
        expect(result).not_to include leo
      end
      context '#authzd_query parity' do
        before do
          subject.register_class(
            Person,
            fields: {
              name: String,
              sign_name: String,
              sign: Relation.new(
                kind: 'one',
                other_type: 'Sign',
                my_field: 'sign_name',
                other_field: 'name'
              )
            }
          )
          subject.register_class(
            Sign,
            fields: {
              name: String,
              element: String,
              ruler: String,
              people: Relation.new(
                kind: 'many',
                other_type: 'Person',
                my_field: 'name',
                other_field: 'sign_name',
              )
            }
          )
        end
        it 'test_authorize_scalar_attribute_eq' do
          subject.load_str <<~POL
            allow(_: Person, "read", _: Sign{element: "fire"});
            allow(_: Person{sign_name}, "read", _: Sign{name: sign_name});
          POL
          query = subject.authzd_query(Person.find('sam'), 'read', Sign)
          expected_signs = %w[pisces aries sagittarius leo].map { |n| Sign.find n }
          expect(query.to_a).to contain_exactly(*expected_signs)
        end

        it 'test_authorize_scalar_attribute_condition' do
          subject.load_str <<~POL
            # signs ruled by jupiter can read their own people
            allow(_: Sign{name, ruler:"jupiter"}, "read", _: Person{sign_name: name});
            # every sign can read a pisces named sam
            allow(_: Sign, "read", _: Person {sign: s, name: "sam"}) if s.name = "pisces";
            # earth signs can read people with air signs
            allow(_: Sign{element: "earth"}, "read", person: Person) if person.sign.element = "air";
          POL

          test = lambda do |person, sign|
            (person.sign == sign && sign.ruler == 'jupiter') ||
              (person.name == 'sam' && person.sign.name == 'pisces') ||
              (sign.element == 'earth' && person.sign.element == 'air')
          end
          Sign.all.each do |sign|
            expected = Person.all.select do |person|
              test[person, sign]
            end
            query = subject.authzd_query sign, 'read', Person
            expect(query.to_a).to contain_exactly(*expected)
          end
        end

        it 'test_partial_isa_with_path' do
          subject.load_str <<~POL
            allow(_, _, _: Person{sign}) if check(sign);
            check(sign: Sign) if sign.name = "cancer";
            check(person: Person) if person.sign.name = "leo";
          POL
          query = subject.authzd_query 'gwen', 'read', Person
          expected = Person.all.select { |person| person.sign.name == 'cancer' }

          expect(query.to_a).to contain_exactly(*expected)
        end

        it 'test_no_relationships' do
          subject.load_str 'allow(_, _, _: Sign{element:"fire"});'
          query = subject.authzd_query 'gwen', 'read', Sign
          expect(query.to_a).to contain_exactly(*Sign.where(element: 'fire'))
        end

        it 'test_neq' do
          subject.load_str 'allow(_, action, _: Sign{name}) if name != action;'
          query = subject.authzd_query 'gwen', 'libra', Sign
          expect(query.to_a).to contain_exactly(*Sign.where.not(name: 'libra'))
        end

        it 'test_relationship' do
          subject.load_str <<~POL
            allow(_, _, person: Person) if
              sign = person.sign and
              sign.name = "cancer" and
              person.name = "eden";
          POL

          query = subject.authzd_query 'gwen', 'read', Person
          expect(query.to_a).to eq([eden])
        end

        it 'test_field_eq' do
          subject.load_str 'allow(_, _, _: Person{name, sign_name: name});'
          query = subject.authzd_query 'gwen', 'read', Person
          expect(query.to_a).to eq([leo])
        end

        it 'test_field_neq' do
          subject.load_str 'allow(_, _, _: Person{name, sign_name}) if name != sign_name;'
          query = subject.authzd_query 'gwen', 'read', Person
          expect(query.to_a).to contain_exactly(*Person.where.not(name: 'leo'))
        end

        it 'test_param_field' do
          subject.load_str 'allow(ruler, element, _: Sign{ruler, element});'
          Sign.all.each do |sign|
            query = subject.authzd_query sign.ruler, sign.element, Sign
            expect(query.to_a).to eq([sign])
          end
        end

        it 'test_field_cmp_rel_field' do
          subject.load_str 'allow(_, _, person: Person) if person.name = person.sign.name;'
          query = subject.authzd_query 'gwen', 'read', Person
          expect(query.to_a).to eq([leo])
        end
      end



      DB_FILE = 'astro_test.db'
      before do # rubocop:disable Metrics/BlockLength
        File.delete DB_FILE if File.exist? DB_FILE
        db = SQLite3::Database.new DB_FILE
        db.execute <<~SQL
          create table signs (
            name varchar(16) not null primary key,
            element varchar(8) not null,
            ruler varchar(8) not null
          );
        SQL

        db.execute <<~SQL
          create table people (
            name varchar(32) not null primary key,
            sign_name varchar(16) not null
          );
        SQL

        ActiveRecord::Base.establish_connection(
          adapter: 'sqlite3',
          database: DB_FILE
        )

        [%w[aries fire mars],
         %w[taurus earth venus],
         %w[gemini air mercury],
         %w[cancer water moon],
         %w[leo fire sun],
         %w[virgo earth mercury],
         %w[libra air venus],
         %w[scorpio water mars],
         %w[sagittarius fire jupiter],
         %w[capricorn earth saturn],
         %w[aquarius air saturn],
         %w[pisces water jupiter]].each do |name, element, ruler|
          Sign.create(name: name, element: element, ruler: ruler)
        end

        [%w[robin scorpio],
         %w[pat taurus],
         %w[dylan virgo],
         %w[terry libra],
         %w[chris aquarius],
         %w[leo leo],
         %w[eden cancer],
         %w[dakota capricorn],
         %w[charlie aries],
         %w[alex gemini],
         %w[sam pisces],
         %w[avery sagittarius]].each do |name, sign|
          Person.create(name: name, sign_name: sign)
        end
      end

      let(:eden) { Person.find 'eden' }
      let(:leo) { Person.find 'leo' }
    end
  end

  class Sign < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = 'name'
    has_many :people, foreign_key: :sign_name
  end

  class Person < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = 'name'
    belongs_to :sign, foreign_key: :sign_name
  end

  class User < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = :name
    belongs_to :org, foreign_key: :org_name
    has_many :org_roles, foreign_key: :user_name
    has_many :repo_roles, foreign_key: :user_name
  end

  class Repo < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = :name
    belongs_to :org, foreign_key: :org_name
    has_many :issues, foreign_key: :repo_name
    has_many :repo_roles, foreign_key: :repo_name
  end

  class Org < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = :name
    has_many :users, foreign_key: :org_name
    has_many :repos, foreign_key: :org_name
    has_many :org_roles, foreign_key: :org_name
  end

  class Issue < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    self.primary_key = :name
    belongs_to :repo, foreign_key: :repo_name
  end

  class RepoRole < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    belongs_to :user, foreign_key: :user_name
    belongs_to :repo, foreign_key: :repo_name
  end

  class OrgRole < ActiveRecord::Base
    include DFH::ActiveRecordFetcher
    belongs_to :user, foreign_key: :user_name
    belongs_to :org, foreign_key: :org_name
  end
end