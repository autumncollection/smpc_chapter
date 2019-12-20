
module DBCommon::Countries
  module Czech
    module SmpcMatcher

      def try_pure_name_match
        true
      end

      def validate_match drug
        validate_match_drug_name_in_chapter1 drug
      end

      def ema_drug_name_match drug_name
        {
          "ADYNOVI 1000IU Prášek pro injekční roztok s rozpouštědlem" => "ADYNOVI 1000 IU / 2 ml prášek a rozpouštědlo pro injekční roztok",
          "ADYNOVI 250IU Prášek pro injekční roztok s rozpouštědlem" => "ADYNOVI 250 IU / 2 ml prášek a rozpouštědlo pro injekční roztok",
          "ADYNOVI 500IU Prášek pro injekční roztok s rozpouštědlem" => "ADYNOVI 500 IU / 2 ml prášek a rozpouštědlo pro injekční roztok",
          "ADYNOVI 2000IU Prášek pro injekční roztok s rozpouštědlem" => "ADYNOVI 2000 IU / 5 ml prášek a rozpouštědlo pro injekční roztok",
          "ALLERGOCROM KOMBI (OČNÍ+NOSNÍ) 20MG/ML+2,8MG/0,14ML Oční kapky, roztok a nosní sprej, roztok" => "Allergocrom nosní sprej Nosní sprej, roztok",
          "AXURA 5MG+10MG+15MG+20MG Potahovaná tableta" => "Axura 5 mg+10 mg+15 mg+20 mg potahované tablety",
          "ENBREL PRO PEDIATRICKÉ POUŽITÍ 10MG Prášek a rozpouštědlo pro injekční roztok" => "ENBREL 10 mg prášek a rozpouštědlo pro injekční roztok pro pediatrické použití",
          "EPTIFIBATIDE ACCORD 2MG/ML Intravenózní podání infuzního roztoku" => "Eptifibatide Accord 2 mg/ml injekční roztok",
          "GONAL-F 300 IU/0,5 ML (22 MIKROGRAMŮ/0,5 ML) Prášek a rozpouštědlo pro injekční roztok" => "GONAL-f 300 IU/0,50 ml (22 mikrogramů/0,50 ml), prášek a rozpouštědlo pro injekční roztok",
          "HBVAXPRO 5MCG Injekční suspenze v předplněné injekční stříkačce" => "HBVAXPRO 5 mikrogramů injekční suspenze v přeplněné injekční stříkačce Vakcína proti hepatitidě typu B (rDNA)",
          "HELICOBACTER TEST INFAI 75MG Prášek pro perorální roztok" => "Helicobacter Test INFAI, 75 mg prášek pro přípravu perorálního roztoku",
          "HELICOBACTER TEST INFAI PRO DĚTI OD 3-11 LET 45MG Prášek pro perorální roztok" => "Helicobacter Test INFAI pro děti ve věku od 3 – 11 let, 45 mg prášku pro přípravu perorálního roztoku.",
          "INOMAX 400PPM MOL/MOL Medicinální plyn, stlačený" => "INOmax 400 ppm mol/mol plyn k inhalaci",
        }.fetch(drug_name, nil)
      end

      def clean_smpc_name name
        clean1 = name.gsub(/\s\(.+\)$/, '')
          .gsub('BUC BUC TBL', 'bukální tablety')
          .gsub('TDR TDR EMP', 'transdermální náplast')
          .gsub('ETP GAS CRS', 'plyn k inhalaci')
          .gsub('DRM GEL SCC', 'gel v sáčku')
          .gsub('SDR INJ SUS VIA', 'injekční suspenze v injekční lahvičce')
          .gsub('SDR INJ SOL VIA', 'injekční roztok v injekční lahvičce')
          .gsub('SDR+IVN INJ SOL VIA', 'injekční roztok v injekční lahvičce')
          .gsub(/rozpustn. tablet./, 'rozpustna tableta')
          .gsub(/tablety?\b/i, 'tableta')
          .gsub('talbey', 'tableta')
          .gsub(/dispergovateln.?/i, 'dispergovatelna')
          .gsub(/prášek pro injekční nebo infuzní roztok a rozpouštědlo/i, 'prášek a rozpouštědlo pro injekční/infuzní roztok')
          .gsub(' nebo ', '/')
          .gsub(/tvrd.?/i, 'tvrda')
          .gsub(/tobolky/i, 'tobolka')
          .gsub(/tobolkách/i, 'tobolka')
          .gsub(/tobolce/i, 'tobolka')
          .gsub('tvrda tobolka', 'tobolka')
          .gsub(/acetyl/i, 'acety')
          .gsub(/tenofovir/i, 'enofovir')
          .gsub(/rasagilinum/, 'rasagiline')
          .gsub(/obalen(e|é)/i, 'obalena')
          .gsub(/Perorální suspenze v předplněném aplikátoru pro perorální podání/i, 'perorální suspenze v předplněném perorálním aplikátoru')
          .gsub(/lyofilizát a rozpouštědlo pro přípravu injekčního roztoku/i, 'lyofilizát pro přípravu injekčního roztoku s rozpouštědlem')
          .gsub(/prášek a roztok pro přípravu injekčního roztoku/i, 'prášek a roztok pro injekční roztok')
          .gsub(/prášek pro injekční roztok s rozpouštědlem/i, 'prášek a rozpouštědlo pro injekční roztok')
          .gsub(/prášek pro injekční roztok a rozpouštědlo v předplněné injekční stříkačce/i, 'prášek a rozpouštědlo pro injekční roztok')
          .gsub(/prášek pro přípravu injekčního roztoku( s rozpouštědlem)?/i, 'prášek a rozpouštědlo pro injekční roztok')
          .gsub(/prášek na přípravu koncentrátu pro infúzní roztok/i, 'prášek pro koncentrát pro infúzní roztok')
          .gsub(/prášek pro přípravu koncentrátu pro přípravu infuzního roztoku/i, 'prášek pro koncentrát pro infúzní roztok')
          .gsub(/prášek pro přípravu perorálního roztoku/i, 'prášek pro perorální roztok')
          .gsub(/prášek pro přípravu perorální suspenze/i, 'prášek pro perorální suspenzi')
          .gsub(/koncentrát pro přípravu infuzního roztoku/i, 'koncentrát pro infúzní roztok')
          .gsub(/intravenózní podání infuzního roztoku/i, 'infuzní roztok')
          .gsub(/injekční roztok v injekční lahvičce/i, 'injekční roztok')
          .gsub(/injekční roztok v?\s?předplněné injekční stříkačce/i, 'injekční roztok')
          .gsub(/subkutánní injekční roztok/i, 'injekční roztok')
          .gsub(/potah.?va?n.?/i, 'potahovana')
          .gsub(/prášek a rozpouštědlo pro injekční suspenzi s prodlouženým uvolňováním/i, 'IMS INJ PLQ SUR ISP')
          .gsub('prodlouženým uvolňováním?', 'prodlouzenym ucinkem')
          .gsub(/měkk.?/i, 'měkká')
          .gsub('injekčního', 'injekční')
          .gsub('roztoku', 'roztok')
          .gsub('pro přípravu infuzního roztoku', 'pro infúzní roztok')
          .gsub('pro p.ípravu peror.ln. suspenze', 'pro perorální suspenzi')
          .gsub(/MEZIN.RODN.CH JEDNOTEK/i, 'IU')
          .gsub(/milion. IU/i, 'MIU')
          .gsub(/mikromol/i, 'mcmol')
          .gsub(/jednotek tvo..c.ch plaky(\s+\(PFU\))?/i, 'PFU')
          .gsub(/jednotek/i, 'u')
          .gsub(/24 hodin/i, '24h')
          .gsub(/nosn. sprej\, roztok/i, 'nosni sprej')
          .gsub(/MIKROGRAM./i, 'mcg')
          .gsub(/ŠUMIV./i, 'šumiva')
          .gsub(/Č.pky/i, 'čipek')
          .gsub(/d.vka/i, 'dav')
          .gsub(/roactemra,/i, 'roactemra')
          .gsub(/Acccord/i, 'accord')
          .gsub(/emulze a suspenze/i, 'suspenze a emulze')
          .gsub(/prášek a rozpouštědlo pro injekční suspenzi s prodlouženým účinkem v předplněném peru/i, 'SDR INJ PLQ SUR PEP')
          .gsub('0,50', '0,5')
          .gsub(' j.', 'u')
          .gsub(/v 1\,0 ml/i, '/ml')
          .gsub(/\,0+\s?ml/, 'ml')
          .gsub(/\,0+\s?mg/, 'mg')
          .gsub(/\/1\s?ml/i, '/ml') # /1 ml -> /ml
          .gsub(/(\d)\,(\d)/, "#{$1}.#{$2}")
          .gsub(',0', '')
          .gsub('mg,', 'mg')
          .gsub(/\.$/, '')
          .gsub('s rozpouštědlem', '')
          # .gsub('pro přípravu injekčního roztoku', 'prášek pro injekční roztok') @TODO: add this substitution and a test for it once tests work again

        clean_text(clean1, clean_dashes: true, clean_punct: true)
      end

    end
  end
end

