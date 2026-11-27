//! The login e-mail; its texts come from the `mail` catalogue (ADR 0101).

use tradocraft_core::translations::Catalogue;

/// Subject and body of the e-mail with the one-time login link, in the language of `texts`.
pub fn login_mail(
    texts: &Catalogue,
    greeting: &str,
    company: &str,
    link: &str,
    minutes: i64,
) -> (String, String) {
    let minutes = minutes.to_string();
    let args = [("company", company), ("minutes", minutes.as_str())];
    let t = |k: &str| texts.format(&format!("mail.portal_login.{k}"), &args);
    let body = format!(
        "{greeting}\n\n{}\n{link}\n\n{}\n{}\n\n{},\n{company}\n",
        t("intro"),
        t("valid"),
        t("ignore"),
        t("regards")
    );
    (t("subject"), body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tradocraft_core::translations::Domain;

    #[test]
    fn every_language_has_the_link_and_greeting() {
        for l in ["nl", "fr", "en", "de", "es", "pt"] {
            let texts = Catalogue::shipped(Domain::Mail, l);
            let (subject, body) =
                login_mail(&texts, "Hello Sam,", "Demo", "https://p/login#token=x", 15);
            assert!(subject.contains("Demo"), "{l}");
            assert!(body.starts_with("Hello Sam,"), "{l}");
            assert!(body.contains("https://p/login#token=x"), "{l}");
            assert!(body.contains("15"), "{l}");
        }
    }
}
