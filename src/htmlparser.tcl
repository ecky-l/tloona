
package provide tloona::htmlparser 1.0

namespace eval ::Tloona::Html {
    # @v HtmlNoEventHandlers: a list of all html elements that are no event handlers
    variable NoEventHandlers {applet base basefont bdo br font frame frameset head html iframe isindex param script style title}
    
    variable EventHandlerAttr {onclick ondblclick onmousedown onmouseup onmouseover onmousemove onmouseout onkeypress onkeydown onkeyup}
    
    # @v HtmlAttr: array of html attributes, special to tags
    variable Tags
    array set Tags {\
        a {accesskey charset coords href hreflang name onblur onfocus rel rev shape tabindex target type}
        abbr {}
        acronym {}
        address {}
        applet {align alt archive code codebase height hspace name object vspace width}
        area {alt accesskey coords href nohref onblur onfocus shape tabindex target}
        b {}
        base {href target}
        basefont {color face size}
        bdo {dir}
        big {}
        blockquote {cite}
        body {alink background bgcolor link onload onunload text vlink}
        br {clear}
        button {accesskey datafld datasrc dataformatas disabled name onblur onfocus tabindex type value}
        caption {align}
        center {}
        cite {}
        code {}
        col {align char charoff span valign width}
        colgroup {align char charoff span valign width}
        dd {}
        del {cite datetime}
        dfn {}
        dir {compact}
        div {align datafld datasrc dataformatas}
        dl {compact}
        dt {}
        em {}
        fieldset {}
        font {color face size}
        form {action accept accept-charset enctype method name onreset onsubmit target}
        frame {frameborder longdesc marginwidth marginheight name noresize scrolling src}
        frameset {cols onload onunload rows}
        h1 {align}
        h2 {align}
        h3 {align}
        h4 {align}
        h5 {align}
        h6 {align}
        head {profile}
        hr {align noshade size width}
        html {version}
        i {}
        iframe {align frameborder height longdesc marginwidth marginheight name scrolling src width}
        img {align alt border height hspace ismap longdesc name src usemap vspace width}
        input {accept accesskey align alt checked datafld datasrc dataformatas disabled ismap maxlength name onblur onchange onfocus onselect readonly size src tabindex type usemap value}
        ins {cite datetime}
        isindex {prompt}
        kbd {}
        label {accesskey for onblur onfocus}
        legend {accesskey align}
        li {type value}
        link {charset href hreflang media rel rev target type}
        map {name}
        menu {compact}
        meta {name content http-equiv scheme}
        noframes {}
        noscript {}
        object {align archive border classid codebase codetype data datafld datasrc dataformatas declare height hspace name standby tabindex type usemap vspace width}
        ol {compact start type}
        optgroup {disabled label}
        option {disabled label selected value}
        p {align}
        param {name value valuetype type}
        pre {width}
        q {cite}
        s {}
        samp {}
        script {charset defer event language for src type}
        select {datafld datasrc dataformatas disabled multiple name onblur onchange onfocus size tabindex}
        small {}
        span {datafld datasrc dataformatas}
        strike {}
        strong {}
        style {media title type}
        sub {}
        sup {}
        table {align border bgcolor cellpadding cellspacing datafld datasrc dataformatas frame rules summary width}
        tbody {align char charoff valign}
        td {abbr align axis bgcolor char charoff colspan headers height nowrap rowspan scope valign width}
        textarea {accesskey cols disabled name onblur onchange onfocus onselect readonly rows tabindex}
        tfoot {align char charoff valign}
        th {abbr align axis bgcolor char charoff colspan headers height nowrap rowspan scope valign width}
        thead {align char charoff valign}
        title {}
        tr {align bgcolor char charoff valign}
        tt {}
        u {}
        ul {compact type}
        var {}
    }
    
}