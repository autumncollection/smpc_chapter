module DBCommon

  module SmpcMatcher

    extend DBCommon::Localized

    include DBCommon::Sources

    # Try pure name match (without url join)
    #
    # Override this in country-specific (to return true) to try a second pass with only matching names (not urls).
    # See {match_drug_to_smpc} about second pass of matching only by name (not urls).
    #
    # @country_specific Optional
    def try_pure_name_match
      false
    end

    # Manual matches of drug_name -> EMA smpc_name (in chapter1 of the SMPC)
    #
    # Override this in country specific to manually match drug name to ema smpc drug name
    #
    # @country_specific Optional
    def ema_drug_name_match drug_name
      nil
    end

    # Manual matches of drug_name -> smpc_name
    #
    # Only used for matches without url (if try_pure_name_match returns true)
    #
    # @country_specific Optional
    def pure_drug_name_match drug_name
      nil
    end

    # Validate if match is really OK
    #
    # This is where country-specific matching checks come in. In Slovenia we check that chapter1 actually includes
    # drug name, otherwise we refuse to match, so we call {validate_match_drug_name_in_chapter1} in country-specific
    # implementation of this method.
    #
    # @country_specific Optional
    def validate_match drug
      true # for example you can use the validation below e.g.: validate_match_drug_name_in_chapter1(drug)
    end

    # Determine drug registered name for smpc matching
    #
    # This is where drug registered name, used for matching is country-specific. In Italy we use registered_name value
    # for drugs that don't have it overidden with producer title. When a registered_name has been changed, we can specify
    # here what version of drug registered name we want to use for smpc matching.
    def drug_registered_name_for_matching item
      item.attributes['data_registered_name']
    end

    DRUG_SMPC_JOIN_QUERY_SELECT = <<-SELECT
      drugs.uuid AS uuid, drugs.data->'smpc' AS data_smpc, drugs.data->>'registered_name' as data_registered_name, drugs.data->>'_original_registered_name' as data_original_registered_name,
      smpcs.uuid AS smpc_uuid, smpcs.data->'smpc'->'sections'->>'1' as smpc_chap1
    SELECT

    # Returns {Backend::Drug} joined with {Backend::Smpc} by url field for given builds
    def drug_smpc_join_query builds
      drugs = Backend::Drug.joins("INNER JOIN smpcs ON drugs.data->>'smpc' = smpcs.data->>'url'")
        .select(DRUG_SMPC_JOIN_QUERY_SELECT)
        .where(build_id: builds, smpcs: {build_id: builds})
    end

    # Returns {Backend::Drug} joined with {Backend::Smpc} by url field for given builds
    # Also takes overrides into account
    def fetch_joined_smpcs builds, filter=false, overrides=true
      drugs = drug_smpc_join_query builds

      if filter
        drugs = drugs.where('drugs.data @> ?', JSON.generate({registered_name: filter}))
      end

      drugs = drugs.order("char_length(smpcs.data->>'chapter1_text'::text) ASC, smpcs.data->>'chapter1_text' ASC") # this is in addition to drugs.data->>'registered_name'
      grouped = drugs.group_by(&:uuid)

      # HANDLE OVERRIDES
      if overrides
        smpcOverrides = Backend::OverrideFieldMetadata.country(country).by_field('smpc').active.map do |meta|
          if not meta.data.fetch('export_only', false)
            [meta.piece_uuid, meta.data['update']]
          end
        end.compact.to_h

        grouped = grouped.map do |uuid, drugs|
          if smpcOverrides.include?(uuid)
            puts "Override smpc url for #{uuid}: #{smpcOverrides[uuid]}"
            group = [uuid, Backend::Drug.select(DRUG_SMPC_JOIN_QUERY_SELECT)
              .where(build_id: builds, smpcs: {build_id: builds})
              .where("drugs.uuid = ?", uuid)
              .where("smpcs.data @> ?", {url: smpcOverrides[uuid]}.to_json)
              .order("smpcs.data->>'chapter1_text' ASC")
              .joins("INNER JOIN smpcs ON 1 = 1").to_a]

            smpcOverrides.delete(uuid)
            puts "Override smpc join query results: #{group[1]}"
            group
          else
            [uuid, drugs]
          end
        end.to_h

        smpcOverrides.each do |uuid, smpc_url|
          grouped[uuid] = Backend::Drug.select(DRUG_SMPC_JOIN_QUERY_SELECT)
            .where(build_id: builds, smpcs: {build_id: builds})
            .where("drugs.uuid = ?", uuid)
            .where("smpcs.data @> ?", {url: smpc_url}.to_json)
            .order("smpcs.data->>'chapter1_text' ASC")
            .joins("INNER JOIN smpcs ON 1 = 1").to_a
        end

        grouped
      else
        grouped
      end
    end

    # Fetch smpcs that do not have a match yet
    #
    # Returns Smpc pieces with joined SmpcMatch
    # (but do have a data.name)
    def fetch_empty_smpcs builds
      Backend::Smpc.build(builds).joins_matches.where('smpc_matches.uuid IS NULL')
    end

    # Retruns [smpc_uuid, smpc_name] pairs
    def fetch_smpcs_uuids_and_names builds, only_empty=true
      query = if only_empty
        fetch_empty_smpcs(builds)
      else
        Backend::Smpc.build(builds)
      end
      smpcs = []
      query.where("smpcs.data @> ?", JSON.generate({status: 'ok'})).select("smpcs.uuid as smpc_uuid, smpcs.data->'smpc'->'sections'->>'1' as smpc_chap1").each do |smpc|
        # it can happen that smpc is status: ok but there is no chapter 1 (because we only require 4.1 to 4.9)
        if smpc.attributes['smpc_chap1'].nil?
          next
        end
        names = chapter1_to_names(smpc.attributes['smpc_chap1'])
        names.each do |name|
          next if name.nil? or name.empty?
          smpcs << [smpc.smpc_uuid, clean_smpc_name(name)]
        end
        smpcs << [smpc.smpc_uuid, clean_smpc_name(Nokogiri::HTML(smpc.attributes['smpc_chap1']).text)]
      end

      smpcs
    end

    # Split Smpc chapter1 to drug names
    def chapter1_to_names chapter1
      if chapter1.nil?
        return []
      end
      chapter1 = Nokogiri::HTML(chapter1).text if chapter1.include?(?<)

      chapter1 = chapter1.gsub(/^Balení pro zahájení léčby/i, '') # multiple dosages can contain this in chapter1 (CZ)
        .gsub(/^Balenie na počiatočnú liečbu/i, '') # SK
        .gsub(/^Balenie na zahájenie liečby \(len u dospievajúcich a detí s telesnou hmotnosťou 50 kg alebo viac a u dospelých\)\,?/i, '') # SK
      # check if registered name contains multiple dosages
      # split the drug to multiple drugs
      nn = chapter1.gsub(/\xE2\x80\x8C/, '').split(' ').first
      names = [chapter1]

      if !nn.blank? && cyrillic?(nn) > 0.6
        transnn = transliterate(nn)
        nnreg = /(?:#{nn}|(?:#{phonemes_regex(transnn)}))/i
        occurences = chapter1.scan(nnreg).uniq # actual occurences of word
        names = chapter1.split(nnreg).drop(1).map do |nam|
          occurences.map do |occ|
            "#{occ}#{nam}".strip.gsub(/\.$/, '').gsub(/^\./, '')
          end
        end.flatten
      elsif !nn.blank? && chapter1.split(nn).length > 2
        # log "Multiple dosages in registered_name: #{chapter1}"
        names = chapter1.split(nn).drop(1).map { |nam|
          "#{nn}#{nam}".strip.gsub(/\.$/, '').gsub(/^\./, '')
        }
      elsif chapter1.include?(?\n)
        # log "Multiple dosages (newline) in registered_name: #{name}"
        names = chapter1.split(?\n).reject{|item| item.gsub(/\xE2\x80\x8C/, '').strip == ''}.map{|item|item.strip}
      end

      names.map {|name| name.gsub("\n", ' ').squeeze(' ')}.reject(&:blank?)
    end

    # Match drug to smpc
    #
    # This method is passed a {Backend::Drug} joined with all possible {Backend::Smpc}s (by url).
    # It tries different ways of finding the correct Smpc for the Drug, returning an array of
    # `[match_type (for stats), [drug.uuid, smpc.uuid], valid boolean]`.
    #
    # About valid flag: Sometimes we find the exact Smpc, but we check additionaly if it is valid (e.g. is
    # drug name present in the first chapter of Smpc). If it is not valid, we still want to save the {Backend::SmpcMatch}
    # so that we remove the drug.smpc url at export.
    def match_drug_to_smpc items, csv_manual_resolver
      regname = drug_registered_name_for_matching(items.first)

      # one url
      if items.length == 1
        return [:one_url, [items.first.uuid, items.first.attributes['smpc_uuid']], validate_match(items.first)]
      end

      # match by manual ema match
      ema_name = ema_drug_name_match(regname)
      unless ema_name.nil?
        items.each do |item|
          names = chapter1_to_names(item.attributes['smpc_chap1'])

          names.each do |name|
            if ema_name == name
              # if validate_match(item)
              # dont validate, this is a manual match
              return [:match_manual_ema, [item.uuid, item.attributes['smpc_uuid']], true]
              # end
            end
          end
        end
      end

      # match by clean_text(name)
      items.each do |item|
        names = chapter1_to_names(item.attributes['smpc_chap1'])
        names.each do |name|
          if clean_text(regname, clean_dashes: true, clean_punct: true) == clean_text(name, clean_dashes: true, clean_punct: true)
            return [:match_name, [item.uuid, item.attributes['smpc_uuid']], validate_match(item)]
          end
        end
      end

      # match by custom clean name
      # all other tests in this method should do this as well
      # combine all items and sort them, only then find the bast match
      # (because currently the first of items that matches will return and other,
      # possibly better matches will not be processed)
      cregname = clean_smpc_name(regname)
      nitems = items.each_with_index.map do |item, i|
        names = chapter1_to_names(item.attributes['smpc_chap1'])

        names.map do |name|
          [name, item, i]
        end
      end.flatten(1)

      matched = nitems.select do |name, item, i|
        cname = clean_smpc_name(name)
        cregname == cname or cname.start_with?(cregname)
      end.sort_by do |name, item, i|
        # puts "NAME: #{regname} -- #{name} // #{DamerauLevenshtein.distance(clean_smpc_name(name), cregname)}"
        [DamerauLevenshtein.distance(clean_smpc_name(name), cregname), i]
      end.first

      if matched
        item = matched[1]
        return [:match_clean_name, [item.uuid, item.attributes['smpc_uuid']], validate_match(item)]
      end


      # multiple dosages
      #
      # In case registered_name is already merged (Champix 0.5mg in 1mg filmsko obložene tablete)
      # We have to try to merge the smpc_chap1 and match that with the registered_name
      reg = /(,\s|-\s|\sin\s|\+\s|\+)/i
      regname.match(reg) do |match|
        separator = match[0]

        matches = []
        items.each_with_index.each do |item, i|
          if item.attributes['smpc_chap1']
            names = chapter1_to_names(item.attributes['smpc_chap1'])
            next if names.length == 1 # not multiple
            smpc_chap_name = DrugRowData.for(country).new(registered_name: names.join(separator)).merge_multiple_dosings

            if clean_smpc_name(regname) == clean_smpc_name(smpc_chap_name) || clean_smpc_name(smpc_chap_name).include?(clean_smpc_name(regname))
              matches << [
                [:match_multiple_dosage, [item.uuid, item.attributes['smpc_uuid']], validate_match(item)],
                DamerauLevenshtein.distance(clean_smpc_name(regname), clean_smpc_name(smpc_chap_name)),
                i
              ]
            end
          end
        end

        if matches.length > 0
          return matches.sort_by do |match, lev, i|
            [lev, i]
          end.first[0]
        end
      end

      # strategy: find matched data in CSV
      csv_response = csv_manual_resolver.find_items(items)
      if csv_response
        return [
          :csv_manual_match,
          [
            csv_response.uuid,
            csv_response.attributes['smpc_uuid'],
            csv_response]]
      end

      csv_manual_resolver.prepare_data_to_write!(
        items,
        items.map { |item| chapter1_to_names(item.attributes['smpc_chap1']) })

      t = "\n\t"
      log "Failed to match: #{items.first.attributes['data_registered_name']}#{t}#{items.map{|i| i.attributes['smpc_chap1']}.uniq.join(t)}"

      return nil
    end

    # Match drug to smpc by pure name (if drug is missing smpc url)
    #
    # This is only called if try_pure_name_match returns true (after url-joined drugs are finished matching)
    def match_drug_to_smpc_pure_name drug, smpcs
      # match by manual name match
      manual_smpc_names = Array(pure_drug_name_match(drug.data_registered_name)).compact
      unless manual_smpc_names.empty?
        smpcs.each do |uuid, smpc_name|
          # names = chapter1_to_names(item.attributes['smpc_chap1'])
          # puts "NAME: #{smpc_name}"
          manual_smpc_names.each do |manual_smpc_name|
            if clean_smpc_name(manual_smpc_name) == clean_smpc_name(smpc_name)
              # dont validate, this is a manual match
              return [:pure_name_match_manual, [drug.uuid, uuid], true]
            end
          end
        end
      end

      # match by name
      regname = clean_smpc_name(drug.data_registered_name)
      smpcs.each do |uuid, name|
        next if uuid == '3bDTdwgXjEzgDVdZH31e4wo9bLi' # stelara 130
        if regname == name or name.start_with?(regname)
          return [:pure_name_match, [drug.uuid, uuid], true]
        end
      end

      # @TODO maybe multiple dosings like in match_drug_to_smpc (without original name)
      # Don't know if this happens (no smpc_url AND already compiled miltiple dosing registered_name)

      # try to match with original_registered_name, if existing (this is used in e.g. slovenia for cleaned multiple dosages names)
      origname = drug.data.fetch('_original_registered_name', nil)
      unless origname.nil?
        regname = clean_smpc_name(origname).gsub(?+, '')
        smpcs.each do |uuid, name|
          if regname == name or name.start_with?(regname)
            return [:pure_name_match_original_name, [drug.uuid, uuid], true]
          end
        end
      end

      return nil
    end

    # Validate drug-smpc match by checking if drug name is present in Smpc's chapter1
    def validate_match_drug_name_in_chapter1 drug, options={}
      options[:transliterate_smpc] ||= false
      if drug.attributes['smpc_uuid'].nil?
        false
      else
        if drug.attributes['smpc_chap1'].nil?
          # no chapter1 text, we can't check validity
          true
        else
          regname = clean_smpc_name(drug.attributes['data_registered_name'])
          firstname = clean_smpc_name(drug.attributes['data_registered_name'].split(' ').first)
          text = drug.attributes['smpc_chap1']
          chap1 = Nokogiri::HTML(text).text
          chap1 = transliterate(chap1) if options[:transliterate_smpc]
          chap1 = clean_smpc_name(chap1)
          matches = chap1.include?(regname) || regname.include?(chap1) || chap1.include?(firstname) || chap1.include?(firstname.gsub(/[^a-z0-9]/, ''))
          if not matches
            # @TODO hardcoded exceptions
            if country == :si
              matches = true if regname.include?('ziprazidon') and chap1.include?('ziprasidon')
              matches = true if regname.include?('alendronska') and chap1.include?('alendronat')
            else
              puts "VALIDATE FAIL!"
            end
          end
          matches
        end
      end
    end

    # Clean Smpc drug name
    #
    # Override this in country-specific with substitutions of different spellings of drugs or pharmaceutical forms.
    def clean_smpc_name name
      clean_text(
        name.gsub(/\s\(.+\)$/, ''), # parenthesis at the end
        clean_dashes: true,
        clean_punct: true,
      )
    end

    # Perform matching algorithm
    #
    # Takes {Backend::Build}(task: smpcmatch) as an argument
    #
    # # First pass
    # We join Drug and Smpc by url (see {fetch_joined_smpcs}) and call {match_drug_to_smpc} for each one.
    #
    # # Second pass
    # If country-specific {try_pure_name_match} returns true, after all url-joined smpcs have been matched,
    # we try to match drugs that still have no smpc match purely by name. This is useful in countries where EMA drugs
    # in official source do not have SMPC links (Slovenia).
    def match build
      stats = { no_match: 0 }

      ActiveRecord::Base.logger = Logger.new(STDOUT)

      build.do_build do

        csv_manual_resolver = CsvManualResolver.new
        csv_manual_resolver.read_data!

        streak = build.crawl.streak(:live).reject{|b| b.task == 'smpcmatch' } + [build]

        # fetch drugs joined to SMPCs by url (grouped by drug uuid)
        groups = fetch_joined_smpcs(streak)

        progressbar "Matching smpcs by url join", groups.count
        Backend::SmpcMatch.transaction do
          instances = []

          # each drug with it's possible related smpcs
          groups.each do |key, items|

            next if items == []
            # order smpcs, first the ones with only one name
            items = items.sort_by do |item|
              chap1 = item.attributes['smpc_chap1']
              names = chapter1_to_names(chap1)
              [names.length == 1 ? 0 : 1, (chap1||'').length, (chap1 || '')]
            end.compact

            result = match_drug_to_smpc(items.to_a, csv_manual_resolver)

            if result
              matched_item = items.find { |item| item.attributes['smpc_uuid'] == result[1][1]}
              puts "STATUS: #{result[0]} // #{matched_item.attributes['data_registered_name']}"
              stats[result[0]] ||= 0
              stats[result[0]] += 1

              instance = Backend::SmpcMatch.new(data: {drug_uuid: result[1][0], smpc_uuid: result[1][1], valid: result[2], match_type: result[0]}, build: build)
              # instance.uuid = instance.generate_uuid
              instance.run_callbacks(:validation)
              instance.run_callbacks(:save)
              instances << instance
            else
              stats[:no_match] += 1
              puts "STATUS: no_match // #{items.first.attributes['data_registered_name']}"
            end

            increment
          end

          Backend::SmpcMatch.import instances
        end

        csv_manual_resolver.write_file

        # fetch drugs joined to SmpcMatch (where SmpcMatch is null)
        if try_pure_name_match
          smpcs = fetch_smpcs_uuids_and_names(streak, true)

          drugs = Backend::Drug.build(streak).joins_smpcs_by_matches.where('smpcs.uuid IS NULL')

          count = drugs.count('drugs.uuid')
          progressbar "Pure name match #{count}/#{smpcs.length}", count
          Backend::SmpcMatch.transaction do
            instances = []
            drugs.each do |drug|
              result = match_drug_to_smpc_pure_name(drug, smpcs)

              if result.nil?
                stats[:no_match] += 1
                puts "STATUS: no_match // #{drug.data_registered_name}"
              else
                stats[result[0]] ||= 0
                stats[result[0]] += 1
                puts "STATUS: #{result[0]} // #{drug.data_registered_name}"

                instance = Backend::SmpcMatch.new(data: {drug_uuid: result[1][0], smpc_uuid: result[1][1], valid: result[2], match_type: result[0]}, build: build)
                instance.run_callbacks(:validation)
                instance.run_callbacks(:save)
                instances << instance
              end
              increment
            end

            Backend::SmpcMatch.import instances
          end
        end
      end
      stats
    end

  end

end
