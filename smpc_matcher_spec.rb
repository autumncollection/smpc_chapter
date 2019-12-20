require './lib/dbcommon.rb'
require './spec/spec_helper.rb'
require './spec/fixtures/testcountry/config.rb'

# SmpcMatcher testing
#
# We can only properly unit-test chapter1_to_names
#
# Country-specific SmpcMatcher tests are using spec helpers
# test_smpc_match and test_smpc_match_pure_name
# which are both calling match_drug_to_smpc and match_drug_to_smpc_pure_name
# (and these then call validate_match_drug_name_in_chapter1).
# This way we can test matches between drug.registered_name and
# smpc.data[smpc][section][1] text for the exact strings that should match
# AND the type of match (as well as validity).
#
# How to write a test for a new country:
# 1. Take the latest released db_revision (or later, if needed)
# 2. See smpcmatcher logs to get a test set of different types of matches
# 3. Test all cases of substitution in country-specific clean_smpc_name
# 4. Test all ema manual matches
# 5. Test cases where validation fails (see logs again)
#
# What's missing?
# .match is not covered (does the query and then calls match_drug_to_smpc)
# .fetch_joined_smpcs is not covered (the overrides part would be nice)
#
# Why so slow?
# Because second pass where we try to match a drug to EVERY smpc
#
describe DBCommon::SmpcMatcher, smpcmatcher: true do

  before(:all) do
    @SmpcMatcher = DBCommon::SmpcMatcher.for(:Testcountry)

    # chapter1_to_names uses .transliterate, which needs to be overriden to handle cyrillic
    @SmpcMatcherCyrillic = DBCommon::SmpcMatcher.for(:bg)
  end

  describe 'match_drug_to_smpc' do
    it 'matches by url when only one smpc is passed' do
      drug = build(:drug_smpc_join)
      expect(@SmpcMatcher.match_drug_to_smpc([drug])[0]).to eq(:one_url)
    end

    it 'matches by clean_text if several are passed' do
      aspirin1 = build(:drug_smpc_join, registered_name: 'Aspirin 2mg', chapter1: '<h1>Aspirin 1 mg</h1>', smpc_uuid: 'aspirin1')
      aspirin2 = build(:drug_smpc_join, registered_name: 'Aspirin 2mg', chapter1: '<h1>Aspirin 2 mg</h1>', smpc_uuid: 'aspirin2')

      match_type, uuids, valid = @SmpcMatcher.match_drug_to_smpc([aspirin1, aspirin2])
      expect(match_type).to eq(:match_name)
      expect(uuids[1]).to eq('aspirin2') # matches the second one, not the first one
    end

    it 'matches by clean_text if several are passed (with multiple dosages in one chapter)' do
      aspirin1 = build(:drug_smpc_join, registered_name: 'Aspirin tableta 2mg', chapter1: '<h1>Aspirin tableta 1 mg</h1>', smpc_uuid: 'aspirin1')
      aspirin2 = build(:drug_smpc_join, registered_name: 'Aspirin tableta 2mg', chapter1: '<h1>Aspirin raztopina za injiciranje 1mg/ml Aspirin tableta 2 mg</h1>', smpc_uuid: 'aspirin2')

      match_type, uuids, valid = @SmpcMatcher.match_drug_to_smpc([aspirin1, aspirin2])
      expect(match_type).to eq(:match_name)
      expect(uuids[1]).to eq('aspirin2') # matches the second one, not the first one
    end

    it 'does not match by clean_text if registered_name is not found in chapter' do
      aspirin1 = build(:drug_smpc_join, registered_name: 'Aspirin tableta 2mg', chapter1: '<h1>Aspirin tableta 1 mg</h1>', smpc_uuid: 'aspirin1')
      aspirin2 = build(:drug_smpc_join, registered_name: 'Aspirin tableta 2mg', chapter1: '<h1>Aspirin raztopina za injiciranje 1mg/ml Aspirin prašek 2 mg</h1>', smpc_uuid: 'aspirin2')

      match = @SmpcMatcher.match_drug_to_smpc([aspirin1, aspirin2])
      expect(match).to be_nil
    end
  end

  describe 'chapter1_to_names' do

    it 'returns one name where there are no repeated first names or newlines' do
      expect(@SmpcMatcher.chapter1_to_names('Thorinane 10 000 IU(100 mg) u 1 ml, otopina za injekciju u napunjenoj štrcaljki')).to eq([
        'Thorinane 10 000 IU(100 mg) u 1 ml, otopina za injekciju u napunjenoj štrcaljki'
      ])
    end

    it 'returns more names if first names are repeated' do
      expect(@SmpcMatcher.chapter1_to_names("<p>Kaspofungin Accord 50 mg prašek za koncentrat za raztopino za infundiranje Kaspofungin Accord 70 mg prašek za koncentrat za raztopino za infundiranje</p>")).to eq([
        'Kaspofungin Accord 50 mg prašek za koncentrat za raztopino za infundiranje',
        'Kaspofungin Accord 70 mg prašek za koncentrat za raztopino za infundiranje'
      ])
      expect(@SmpcMatcher.chapter1_to_names("<p>Abc 1<br/>Abc 2</p>")).to eq([
        'Abc 1',
        'Abc 2'
      ])
    end

    it 'returns more names if there are newlines' do
      expect(@SmpcMatcher.chapter1_to_names("Abc 1\nDfe 2")).to eq([
        'Abc 1',
        'Dfe 2'
      ])
    end

    it 'returns empty array if string is nil' do
      expect(@SmpcMatcher.chapter1_to_names(nil)).to eq([])
    end

    it 'removes string "packaging for beggining of therapy" when at beginning of chapter' do
      expect(@SmpcMatcher.chapter1_to_names("Balení pro zahájení léčby\nViagra 1mg\nViagra 2mg\nViagra 3mg")).to eq([
        'Viagra 1mg',
        'Viagra 2mg',
        'Viagra 3mg',
      ])

      expect(@SmpcMatcher.chapter1_to_names("Balenie na počiatočnú liečbu\nViagra 1mg\nViagra 2mg\nViagra 3mg")).to eq([
        'Viagra 1mg',
        'Viagra 2mg',
        'Viagra 3mg',
      ])

      expect(@SmpcMatcher.chapter1_to_names("Balenie na zahájenie liečby (len u dospievajúcich a detí s telesnou hmotnosťou 50 kg alebo viac a u dospelých),\nVimpat 50mg\nVimpat 100mg")).to eq([
        'Vimpat 50mg',
        'Vimpat 100mg',
      ])

    end

    it 'returns more names if name is repeated in latin after cyrillic' do
      expect(@SmpcMatcherCyrillic.chapter1_to_names("<p>Тридерм 0,5 mg/10 mg/1 mg/g крем Triderm 0,5 mg/10 mg/1 mg/g cream</p>")).to eq([
        "Тридерм 0,5 mg/10 mg/1 mg/g крем",
        "Triderm 0,5 mg/10 mg/1 mg/g крем",
        "Тридерм 0,5 mg/10 mg/1 mg/g cream",
        "Triderm 0,5 mg/10 mg/1 mg/g cream"
      ])
    end

    it 'doesn\'t fail when given empty value' do
      expect(@SmpcMatcher.chapter1_to_names('')).to eq([])
      expect(@SmpcMatcher.chapter1_to_names(nil)).to eq([])
    end

    it 'handles phonemes with cyrillic split (while preserving input)' do
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Maдопар 100 mg/25 mg диспергиращи се таблетки Madopar 100 mg/25 mg dispersible tablets")).to eq([
        "Maдопар 100 mg/25 mg диспергиращи се таблетки",
        "Madopar 100 mg/25 mg диспергиращи се таблетки",
        "Maдопар 100 mg/25 mg dispersible tablets",
        "Madopar 100 mg/25 mg dispersible tablets"
      ])

      expect(@SmpcMatcherCyrillic.chapter1_to_names("Золадекс LА 10,8 mg имплантат Zoladex LA 10.8 mg implant")).to eq([
        "Золадекс LА 10,8 mg имплантат", "Zoladex LА 10,8 mg имплантат", "Золадекс LA 10.8 mg implant", "Zoladex LA 10.8 mg implant"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Зокор 20 mg филмирани таблетки Zocor 20 mg film-coated tablets")).to eq([
        "Зокор 20 mg филмирани таблетки", "Zocor 20 mg филмирани таблетки", "Зокор 20 mg film-coated tablets", "Zocor 20 mg film-coated tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Зинат 250 mg филмирани таблетки Zinnat 250 mg film-coated tablets")).to eq([
        "Зинат 250 mg филмирани таблетки", "Zinnat 250 mg филмирани таблетки", "Зинат 250 mg film-coated tablets", "Zinnat 250 mg film-coated tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Ксизал 5 mg филмирани таблетки Xyzal 5 mg film-coated tablets")).to eq([
        "Ксизал 5 mg филмирани таблетки", "Xyzal 5 mg филмирани таблетки", "Ксизал 5 mg film-coated tablets", "Xyzal 5 mg film-coated tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Валсакор 320 mg филмирани таблетки Valsacor320 mg film-coated tablets")).to eq([
        "Валсакор 320 mg филмирани таблетки", "Valsacor 320 mg филмирани таблетки", "Валсакор320 mg film-coated tablets", "Valsacor320 mg film-coated tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Симбикорт 160 микрограма/4,5 микрограма/впръскване, суспензия под налягане за инхалация Symbicort 160 micrograms/4.5 micrograms/actuation pressurised inhalation, suspension")).to eq([
        "Симбикорт 160 микрограма/4,5 микрограма/впръскване, суспензия под налягане за инхалация",
        "Symbicort 160 микрограма/4,5 микрограма/впръскване, суспензия под налягане за инхалация",
        "Симбикорт 160 micrograms/4.5 micrograms/actuation pressurised inhalation, suspension",
        "Symbicort 160 micrograms/4.5 micrograms/actuation pressurised inhalation, suspension"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Бизогамма 5 mg филмирани таблетки Bisogamma 5 mg film-coated tablets")).to eq([
        "Бизогамма 5 mg филмирани таблетки", "Bisogamma 5 mg филмирани таблетки", "Бизогамма 5 mg film-coated tablets", "Bisogamma 5 mg film-coated tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Оспамокс 500 mg/5ml прах за перорална суспензия Ospamox 500 mg/5ml powder for oral suspension")).to eq([
        "Оспамокс 500 mg/5ml прах за перорална суспензия",
        "Ospamox 500 mg/5ml прах за перорална суспензия",
        "Оспамокс 500 mg/5ml powder for oral suspension",
        "Ospamox 500 mg/5ml powder for oral suspension"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("ДИКЛОПРАМ 75 mg/20 mg твърди капсули с изменено освобождаване DICLOPRAM 75 mg/20 mg modified-release capsules, hard")).to eq([
        "ДИКЛОПРАМ 75 mg/20 mg твърди капсули с изменено освобождаване",
        "DICLOPRAM 75 mg/20 mg твърди капсули с изменено освобождаване",
        "ДИКЛОПРАМ 75 mg/20 mg modified-release capsules, hard",
        "DICLOPRAM 75 mg/20 mg modified-release capsules, hard"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Ренитек 20 mg таблетки Renitec 20 mg tablets")).to eq([
        "Ренитек 20 mg таблетки", "Renitec 20 mg таблетки", "Ренитек 20 mg tablets", "Renitec 20 mg tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Пулмикорт Турбухалер 200 микрограма/доза, прах за инхалация Pulmicort Turbuhaler 200 micrograms/dose, inhalation powder")).to eq([
        "Пулмикорт Турбухалер 200 микрограма/доза, прах за инхалация",
        "Pulmicort Турбухалер 200 микрограма/доза, прах за инхалация",
        "Пулмикорт Turbuhaler 200 micrograms/dose, inhalation powder",
        "Pulmicort Turbuhaler 200 micrograms/dose, inhalation powder"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Нексиум 40 mg стомашно-устойчиви таблетки Nexium 40 mg gastro-resistant tablets")).to eq([
        "Нексиум 40 mg стомашно-устойчиви таблетки",
        "Nexium 40 mg стомашно-устойчиви таблетки",
        "Нексиум 40 mg gastro-resistant tablets",
        "Nexium 40 mg gastro-resistant tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Назонекс 50 микрограма/впръскване спрей за нос, суспензия Nasonex 50 micrograms/actuation, nasal spray, suspension")).to eq([
        "Назонекс 50 микрограма/впръскване спрей за нос, суспензия",
        "Nasonex 50 микрограма/впръскване спрей за нос, суспензия",
        "Назонекс 50 micrograms/actuation, nasal spray, suspension",
        "Nasonex 50 micrograms/actuation, nasal spray, suspension"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Лексотан 3 mg таблетки Lexotan 3 mg tablets")).to eq([
        "Лексотан 3 mg таблетки", "Lexotan 3 mg таблетки", "Лексотан 3 mg tablets", "Lexotan 3 mg tablets"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Дормикум 5 mg/ml инжекционен разтвор Dormicum 5 mg/ml solution for injection")).to eq([
        "Дормикум 5 mg/ml инжекционен разтвор", "Dormicum 5 mg/ml инжекционен разтвор", "Дормикум 5 mg/ml solution for injection", "Dormicum 5 mg/ml solution for injection"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Дипросалик 0,5 mg/g + 20 mg/g дермален разтвор Diprosalic 0,5 mg/g + 20 mg/g cutaneous solution")).to eq([
        "Дипросалик 0,5 mg/g + 20 mg/g дермален разтвор",
        "Diprosalic 0,5 mg/g + 20 mg/g дермален разтвор",
        "Дипросалик 0,5 mg/g + 20 mg/g cutaneous solution",
        "Diprosalic 0,5 mg/g + 20 mg/g cutaneous solution"
      ])
      expect(@SmpcMatcherCyrillic.chapter1_to_names("Аркоксия 120 mg филмирани таблетки Arcoxia 120 mg film-coated tablets")).to eq([
        "Аркоксия 120 mg филмирани таблетки", "Arcoxia 120 mg филмирани таблетки", "Аркоксия 120 mg film-coated tablets", "Arcoxia 120 mg film-coated tablets"
      ])
    end
  end

end
