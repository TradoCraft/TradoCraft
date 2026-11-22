//! Parsing incoming e-mail (RFC 5322) into the fields the helpdesk needs.

use mail_parser::{AddressList, MessageParser};

#[derive(Debug, Clone, PartialEq)]
pub struct InboundEmail {
    /// Without angle brackets.
    pub message_id: Option<String>,
    /// In-Reply-To and References, without angle brackets, most recent last.
    pub references: Vec<String>,
    pub from_address: String,
    pub from_name: String,
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub subject: String,
    /// Plain text body (HTML converted to text when there is no text part).
    pub body: String,
    /// Files attached to the message (name as sent, may be empty).
    pub attachments: Vec<InboundAttachment>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct InboundAttachment {
    pub filename: String,
    pub data: Vec<u8>,
}

fn addresses(a: Option<AddressList<'_>>) -> Vec<String> {
    a.into_iter()
        .flat_map(|list| list.mailboxes())
        .filter_map(|x| x.address())
        .map(|s| s.to_lowercase())
        .collect()
}

fn strip_brackets(s: &str) -> String {
    s.trim()
        .trim_start_matches('<')
        .trim_end_matches('>')
        .to_string()
}

pub fn parse(raw: &[u8]) -> Option<InboundEmail> {
    let m = MessageParser::default().parse(raw)?;
    let from = m.from().and_then(|a| a.mailboxes().next());
    let mut references: Vec<String> = m
        .references()
        .into_iter()
        .flat_map(|list| list.iter())
        .map(strip_brackets)
        .collect();
    for r in m.in_reply_to().into_iter().flat_map(|list| list.iter()) {
        let r = strip_brackets(r);
        if !references.contains(&r) {
            references.push(r);
        }
    }
    let body = m
        .body_text(0)
        .map(|b| b.into_owned())
        .or_else(|| m.body_html(0).map(|h| html_to_text(&h)))
        .unwrap_or_default();
    Some(InboundEmail {
        message_id: m.message_id().map(strip_brackets),
        references,
        from_address: from
            .and_then(|a| a.address())
            .unwrap_or_default()
            .to_lowercase(),
        from_name: from.and_then(|a| a.name()).unwrap_or_default().to_string(),
        to: addresses(m.to()),
        cc: addresses(m.cc()),
        subject: m.subject().unwrap_or_default().trim().to_string(),
        body: body
            .replace("\r\n", "\n")
            .replace('\u{a0}', " ")
            .trim()
            .to_string(),
        attachments: m
            .attachments()
            .map(|a| InboundAttachment {
                filename: a.attachment_name().unwrap_or_default().to_string(),
                data: a.decoded().into_owned(),
            })
            .collect(),
    })
}

/// Very small HTML-to-text conversion for HTML-only mails: drops tags, keeps line breaks.
fn html_to_text(html: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    let mut tag = String::new();
    for c in html.chars() {
        match c {
            '<' => {
                in_tag = true;
                tag.clear();
            }
            '>' if in_tag => {
                in_tag = false;
                let t = tag.trim_start_matches('/').to_lowercase();
                if t.starts_with("br")
                    || t.starts_with("p")
                    || t.starts_with("div")
                    || t.starts_with("li")
                {
                    out.push('\n');
                }
            }
            _ if in_tag => tag.push(c),
            _ => out.push(c),
        }
    }
    out.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_reply() {
        let raw = b"From: Anna Peeters <Anna@Alpha.example>\r\n\
To: sales@example.com\r\n\
Cc: boss@alpha.example\r\n\
Subject: Re: Offerte Q2026-00001 [Ticket#T2026-00003]\r\n\
Message-ID: <abc123@alpha.example>\r\n\
In-Reply-To: <out-1@example.com>\r\n\
References: <first@example.com> <out-1@example.com>\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
\r\n\
Akkoord, u mag leveren.\r\n";
        let e = parse(raw).unwrap();
        assert_eq!(e.from_address, "anna@alpha.example");
        assert_eq!(e.from_name, "Anna Peeters");
        assert_eq!(e.message_id.as_deref(), Some("abc123@alpha.example"));
        assert_eq!(e.references, vec!["first@example.com", "out-1@example.com"]);
        assert_eq!(e.cc, vec!["boss@alpha.example"]);
        assert_eq!(e.body, "Akkoord, u mag leveren.");
    }

    #[test]
    fn attachments_are_extracted() {
        let raw = b"From: x@y.example\r\nSubject: Photo\r\nMIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=\"b1\"\r\n\r\n\
--b1\r\nContent-Type: text/plain\r\n\r\nSee attached\r\n\
--b1\r\nContent-Type: application/pdf; name=\"plan.pdf\"\r\n\
Content-Disposition: attachment; filename=\"plan.pdf\"\r\n\
Content-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQK\r\n--b1--\r\n";
        let e = parse(raw).unwrap();
        assert_eq!(e.body, "See attached");
        assert_eq!(e.attachments.len(), 1);
        assert_eq!(e.attachments[0].filename, "plan.pdf");
        assert_eq!(e.attachments[0].data, b"%PDF-1.4\n");
    }

    #[test]
    fn html_only_mail_becomes_text() {
        let raw = b"From: x@y.example\r\nSubject: Hi\r\nContent-Type: text/html\r\n\r\n<p>Hello&nbsp;there</p><p>Second</p>";
        assert_eq!(parse(raw).unwrap().body, "Hello there\nSecond");
    }
}
