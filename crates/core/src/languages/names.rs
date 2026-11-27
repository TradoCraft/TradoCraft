//! Display names of the ISO 639-1 languages: the English name and the endonym (the language's
//! own name, capitalised for use in a list). A small static table instead of CLDR data keeps the
//! dependency footprint at zero; the Flutter app carries the same table in
//! `app/lib/l10n/language_names.dart` (a test keeps the two equal).

/// `(code, English name, endonym)` for every code of [`crate::language::ISO_639_1`], same order.
pub const LANGUAGE_NAMES: &[(&str, &str, &str)] = &[
    ("aa", "Afar", "Afaraf"),
    ("ab", "Abkhazian", "Аҧсуа бызшәа"),
    ("ae", "Avestan", "Avesta"),
    ("af", "Afrikaans", "Afrikaans"),
    ("ak", "Akan", "Akan"),
    ("am", "Amharic", "አማርኛ"),
    ("an", "Aragonese", "Aragonés"),
    ("ar", "Arabic", "العربية"),
    ("as", "Assamese", "অসমীয়া"),
    ("av", "Avaric", "Авар мацӀ"),
    ("ay", "Aymara", "Aymar aru"),
    ("az", "Azerbaijani", "Azərbaycan dili"),
    ("ba", "Bashkir", "Башҡорт теле"),
    ("be", "Belarusian", "Беларуская"),
    ("bg", "Bulgarian", "Български"),
    ("bh", "Bihari", "भोजपुरी"),
    ("bi", "Bislama", "Bislama"),
    ("bm", "Bambara", "Bamanankan"),
    ("bn", "Bengali", "বাংলা"),
    ("bo", "Tibetan", "བོད་ཡིག"),
    ("br", "Breton", "Brezhoneg"),
    ("bs", "Bosnian", "Bosanski"),
    ("ca", "Catalan", "Català"),
    ("ce", "Chechen", "Нохчийн мотт"),
    ("ch", "Chamorro", "Chamoru"),
    ("co", "Corsican", "Corsu"),
    ("cr", "Cree", "ᓀᐦᐃᔭᐍᐏᐣ"),
    ("cs", "Czech", "Čeština"),
    ("cu", "Church Slavic", "Ѩзыкъ словѣньскъ"),
    ("cv", "Chuvash", "Чӑваш чӗлхи"),
    ("cy", "Welsh", "Cymraeg"),
    ("da", "Danish", "Dansk"),
    ("de", "German", "Deutsch"),
    ("dv", "Divehi", "ދިވެހި"),
    ("dz", "Dzongkha", "རྫོང་ཁ"),
    ("ee", "Ewe", "Eʋegbe"),
    ("el", "Greek", "Ελληνικά"),
    ("en", "English", "English"),
    ("eo", "Esperanto", "Esperanto"),
    ("es", "Spanish", "Español"),
    ("et", "Estonian", "Eesti"),
    ("eu", "Basque", "Euskara"),
    ("fa", "Persian", "فارسی"),
    ("ff", "Fulah", "Fulfulde"),
    ("fi", "Finnish", "Suomi"),
    ("fj", "Fijian", "Vosa Vakaviti"),
    ("fo", "Faroese", "Føroyskt"),
    ("fr", "French", "Français"),
    ("fy", "Western Frisian", "Frysk"),
    ("ga", "Irish", "Gaeilge"),
    ("gd", "Scottish Gaelic", "Gàidhlig"),
    ("gl", "Galician", "Galego"),
    ("gn", "Guarani", "Avañe'ẽ"),
    ("gu", "Gujarati", "ગુજરાતી"),
    ("gv", "Manx", "Gaelg"),
    ("ha", "Hausa", "Hausa"),
    ("he", "Hebrew", "עברית"),
    ("hi", "Hindi", "हिन्दी"),
    ("ho", "Hiri Motu", "Hiri Motu"),
    ("hr", "Croatian", "Hrvatski"),
    ("ht", "Haitian Creole", "Kreyòl ayisyen"),
    ("hu", "Hungarian", "Magyar"),
    ("hy", "Armenian", "Հայերեն"),
    ("hz", "Herero", "Otjiherero"),
    ("ia", "Interlingua", "Interlingua"),
    ("id", "Indonesian", "Bahasa Indonesia"),
    ("ie", "Interlingue", "Interlingue"),
    ("ig", "Igbo", "Asụsụ Igbo"),
    ("ii", "Sichuan Yi", "ꆈꌠꉙ"),
    ("ik", "Inupiaq", "Iñupiaq"),
    ("io", "Ido", "Ido"),
    ("is", "Icelandic", "Íslenska"),
    ("it", "Italian", "Italiano"),
    ("iu", "Inuktitut", "ᐃᓄᒃᑎᑐᑦ"),
    ("ja", "Japanese", "日本語"),
    ("jv", "Javanese", "Basa Jawa"),
    ("ka", "Georgian", "ქართული"),
    ("kg", "Kongo", "Kikongo"),
    ("ki", "Kikuyu", "Gĩkũyũ"),
    ("kj", "Kuanyama", "Kuanyama"),
    ("kk", "Kazakh", "Қазақ тілі"),
    ("kl", "Kalaallisut", "Kalaallisut"),
    ("km", "Khmer", "ខ្មែរ"),
    ("kn", "Kannada", "ಕನ್ನಡ"),
    ("ko", "Korean", "한국어"),
    ("kr", "Kanuri", "Kanuri"),
    ("ks", "Kashmiri", "कॉशुर"),
    ("ku", "Kurdish", "Kurdî"),
    ("kv", "Komi", "Коми кыв"),
    ("kw", "Cornish", "Kernewek"),
    ("ky", "Kyrgyz", "Кыргызча"),
    ("la", "Latin", "Latine"),
    ("lb", "Luxembourgish", "Lëtzebuergesch"),
    ("lg", "Ganda", "Luganda"),
    ("li", "Limburgish", "Limburgs"),
    ("ln", "Lingala", "Lingála"),
    ("lo", "Lao", "ລາວ"),
    ("lt", "Lithuanian", "Lietuvių"),
    ("lu", "Luba-Katanga", "Kiluba"),
    ("lv", "Latvian", "Latviešu"),
    ("mg", "Malagasy", "Malagasy"),
    ("mh", "Marshallese", "Kajin M̧ajeļ"),
    ("mi", "Māori", "Te reo Māori"),
    ("mk", "Macedonian", "Македонски"),
    ("ml", "Malayalam", "മലയാളം"),
    ("mn", "Mongolian", "Монгол"),
    ("mr", "Marathi", "मराठी"),
    ("ms", "Malay", "Bahasa Melayu"),
    ("mt", "Maltese", "Malti"),
    ("my", "Burmese", "မြန်မာ"),
    ("na", "Nauru", "Dorerin Naoero"),
    ("nb", "Norwegian Bokmål", "Norsk bokmål"),
    ("nd", "North Ndebele", "IsiNdebele"),
    ("ne", "Nepali", "नेपाली"),
    ("ng", "Ndonga", "Owambo"),
    ("nl", "Dutch", "Nederlands"),
    ("nn", "Norwegian Nynorsk", "Norsk nynorsk"),
    ("no", "Norwegian", "Norsk"),
    ("nr", "South Ndebele", "IsiNdebele"),
    ("nv", "Navajo", "Diné bizaad"),
    ("ny", "Chichewa", "ChiCheŵa"),
    ("oc", "Occitan", "Occitan"),
    ("oj", "Ojibwe", "ᐊᓂᔑᓈᐯᒧᐎᓐ"),
    ("om", "Oromo", "Afaan Oromoo"),
    ("or", "Odia", "ଓଡ଼ିଆ"),
    ("os", "Ossetian", "Ирон æвзаг"),
    ("pa", "Punjabi", "ਪੰਜਾਬੀ"),
    ("pi", "Pali", "पालि"),
    ("pl", "Polish", "Polski"),
    ("ps", "Pashto", "پښتو"),
    ("pt", "Portuguese", "Português"),
    ("qu", "Quechua", "Runa Simi"),
    ("rm", "Romansh", "Rumantsch"),
    ("rn", "Rundi", "Ikirundi"),
    ("ro", "Romanian", "Română"),
    ("ru", "Russian", "Русский"),
    ("rw", "Kinyarwanda", "Ikinyarwanda"),
    ("sa", "Sanskrit", "संस्कृतम्"),
    ("sc", "Sardinian", "Sardu"),
    ("sd", "Sindhi", "سنڌي"),
    ("se", "Northern Sami", "Davvisámegiella"),
    ("sg", "Sango", "Yângâ tî sängö"),
    ("si", "Sinhala", "සිංහල"),
    ("sk", "Slovak", "Slovenčina"),
    ("sl", "Slovenian", "Slovenščina"),
    ("sm", "Samoan", "Gagana Sāmoa"),
    ("sn", "Shona", "ChiShona"),
    ("so", "Somali", "Soomaali"),
    ("sq", "Albanian", "Shqip"),
    ("sr", "Serbian", "Српски"),
    ("ss", "Swati", "SiSwati"),
    ("st", "Southern Sotho", "Sesotho"),
    ("su", "Sundanese", "Basa Sunda"),
    ("sv", "Swedish", "Svenska"),
    ("sw", "Swahili", "Kiswahili"),
    ("ta", "Tamil", "தமிழ்"),
    ("te", "Telugu", "తెలుగు"),
    ("tg", "Tajik", "Тоҷикӣ"),
    ("th", "Thai", "ไทย"),
    ("ti", "Tigrinya", "ትግርኛ"),
    ("tk", "Turkmen", "Türkmençe"),
    ("tl", "Tagalog", "Tagalog"),
    ("tn", "Tswana", "Setswana"),
    ("to", "Tongan", "Lea faka-Tonga"),
    ("tr", "Turkish", "Türkçe"),
    ("ts", "Tsonga", "Xitsonga"),
    ("tt", "Tatar", "Татар теле"),
    ("tw", "Twi", "Twi"),
    ("ty", "Tahitian", "Reo Tahiti"),
    ("ug", "Uyghur", "ئۇيغۇرچە"),
    ("uk", "Ukrainian", "Українська"),
    ("ur", "Urdu", "اردو"),
    ("uz", "Uzbek", "Oʻzbekcha"),
    ("ve", "Venda", "Tshivenḓa"),
    ("vi", "Vietnamese", "Tiếng Việt"),
    ("vo", "Volapük", "Volapük"),
    ("wa", "Walloon", "Walon"),
    ("wo", "Wolof", "Wolof"),
    ("xh", "Xhosa", "IsiXhosa"),
    ("yi", "Yiddish", "ייִדיש"),
    ("yo", "Yoruba", "Yorùbá"),
    ("za", "Zhuang", "Saɯ cueŋƅ"),
    ("zh", "Chinese", "中文"),
    ("zu", "Zulu", "IsiZulu"),
];

/// The language's own name (`Nederlands`, `Français`), or `None` for an unknown code.
pub fn endonym(code: &str) -> Option<&'static str> {
    lookup(code).map(|(_, _, n)| *n)
}

/// The English name (`Dutch`, `French`), or `None` for an unknown code.
pub fn english_name(code: &str) -> Option<&'static str> {
    lookup(code).map(|(_, e, _)| *e)
}

fn lookup(code: &str) -> Option<&'static (&'static str, &'static str, &'static str)> {
    LANGUAGE_NAMES
        .binary_search_by(|(c, _, _)| (*c).cmp(code))
        .ok()
        .map(|i| &LANGUAGE_NAMES[i])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::language::ISO_639_1;

    #[test]
    fn one_name_per_iso_code_in_the_same_order() {
        let codes: Vec<&str> = LANGUAGE_NAMES.iter().map(|(c, _, _)| *c).collect();
        assert_eq!(codes, ISO_639_1);
        assert_eq!(endonym("nl"), Some("Nederlands"));
        assert_eq!(english_name("pt"), Some("Portuguese"));
        assert_eq!(endonym("xx"), None);
    }

    #[test]
    fn flutter_table_is_the_same() {
        let dart = include_str!("../../../../app/lib/l10n/language_names.dart");
        for (code, english, own) in LANGUAGE_NAMES {
            let own = own.replace('\'', "\\'");
            let line = format!("  '{code}': ('{english}', '{own}'),");
            assert!(dart.contains(&line), "missing in the Dart table: {line}");
        }
    }
}
