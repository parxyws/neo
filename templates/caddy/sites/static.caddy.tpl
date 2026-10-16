# Managed by neo — static website
{{SERVER_NAMES_COMMA}} {
    root * {{ROOT}}
    encode zstd gzip
    import security_headers
{{HSTS_LINE}}
    import hide_dotfiles
    file_server
}
