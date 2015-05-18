package text.markdown
{
    import flash.utils.ByteArray;

    /* Global default settings */
    
    internal var g_empty_element_suffix:String = " />"; // Change to ">" for HTML output
    internal var g_tab_width:uint = 4;
    
    /* Globals */
    
    internal var g_nested_brackets:String = build_nested_brackets();
    
    // Table of hash values for escaped characters
    internal var g_escape_table:Object = build_escape_table( "\\`*_{}[]()>#+-.!" );
    
    
    // Global hashes, used by various utility routines
    internal var g_urls:Object = {};
    internal var g_titles:Object = {};
    internal var g_html_blocks:Object = {};
    
    internal var g_list_level:uint = 0;
    
    /* Note:
       original markdown use md5_hex() to produce digests
       we replace it with a ELF hash
       which produce 32bit digests (that should be good enough)
    */
    internal function elf_hex( str:String ):String
    {
        var bytes:ByteArray = new ByteArray();
            bytes.writeUTFBytes( str );
        var hash:uint;
        var x:uint;
        
        var i:uint;
        var c:uint;
        var len:uint = bytes.length;
        bytes.position = 0;
        for( i = 0; i < len; i++ )
        {
            c    = uint( bytes[ i ] );
            hash = uint( hash << 4 ) + c;
            x    = uint( hash & 0xF0000000 );
            
            if( x != 0 )
            {
                hash = uint( hash ^ (x >>> 24) );
            }
            
            hash = uint( hash & ~x );
        }
        
        return hash.toString(16);
    }
    
    internal function build_escape_table( chars:String ):Object
    {
        var o:Object = {};
        var i:uint;
        var len:uint = chars.length;
        var c:String;
        for( i = 0; i < len; i++ )
        {
            c = chars.charAt( i );
            o[ c ] = elf_hex( c );
        }
        return o;
    }
    
    internal function build_nested_brackets():String
    {
        /*
		(					# wrap whole match in $1
		  \[
		    ($g_nested_brackets)	# link text = $2
		  \]
        
        */
        
        
        /*
		text = text.replace(/
		(							// wrap whole match in $1
		  \[
		  (
		   (?:
		   \[[^\]]*\]		// allow brackets nested one level
		   |
		   [^\[]			// or anything else
		   )*
		  )
		  \]
		
		*/
		
        var p:String = "";
            /*
            p += "(?:";        // Atomic matching
            p += "  [^\\[\\]]+"; // Anything other than brackets
            p += "  |";
            p += "  \\["; // Recursive set of nested brackets
            p += "   *";
            //p += "    (?:";
            //p += "      \\[[^\\]]*\\]";
            //p += "      |";
            //p += "      [^\\[]";
            //p += "    )*";
            p += "  \\]";
            p += ")*";
            */
            //p += "  (";
            p += "    (?:";
            p += "    \\[[^\\]]*\\]"; // allow brackets nested one level
            p += "    |";
            p += "    [^\\[]";     // or anything else
            p += "    )*";
            //p += "  )";
            
        return p;
    }
    
    /**
     * Main function. The order in which other subs are called here is
     * essential. Link and image substitutions need to happen before
     * _EscapeSpecialChars(), so that any *'s or _'s in the <a>
     * and <img> tags get encoded.
     */ 
    public function Markdown( txt:String ):String
    {
        // Clear the global hashes. If we don't clear these, you get conflicts
        // from other articles when generating a page which contains more than
        // one article (e.g. an index page that shows the N most recent articles):
        g_urls = {};
        g_titles = {};
        g_html_blocks = {};
        
        // Standardize line endings:
        txt = txt.replace( /\r\n/g, "\n" ); // DOS to Unix
	    txt = txt.replace(   /\r/g, "\n" );   // Mac to Unix
        
        // Make sure $text ends with a couple of newlines:
        txt += "\n\n";
        
        // Convert all tabs to spaces.
        txt = _Detab( txt );
        
        // Strip any lines consisting only of spaces and tabs.
        // This makes subsequent regexen easier to write, because we can
        // match consecutive blank lines with /\n+/ instead of something
        // contorted like /[ \t]*\n+/ .
        txt = txt.replace( /^[ \t]+$/mg, "" );
        
        // Turn block-level HTML blocks into hash entries
        txt = _HashHTMLBlocks( txt );
        
        // Strip link definitions, store in hashes.
        txt = _StripLinkDefinitions( txt );
        
        txt = _RunBlockGamut( txt );
        
        txt = _UnescapeSpecialChars( txt );
        
        return txt + "\n";
    }
    
    /**
     * Strips link definitions from text, stores the URLs and titles in
     * hash references.
     */ 
    internal function _StripLinkDefinitions( txt:String ):String
    {
        var less_than_tab:uint = g_tab_width - 1;
        
        var p:String = "";
            p += "^[ ]{0,"+less_than_tab+"}\\[(.+)\\]:"; // id = $1
            p += "  [ \\t]*";
            p += "  \\n?";              // maybe *one* newline
            p += "  [ \\t]*";
            p += "<?(\\S+?)>?";         // url = $2
            p += "  [ \\t]*";
            p += "  \\n?";              // maybe one newline
            p += "  [ \\t]*";
            p += "(?:";
            p += "    (?<=\\s)";        // lookbehind for whitespace
            p += "    [\"(]";
            p += "    (.+?)";           // title = $3
            p += "    [\")]";
            p += "    [ \\t]*";
            p += ")?";                  // title is optional
            p += "(?:\\n+|\\Z)";
    
        var re:RegExp = new RegExp( p , "mx" );
        txt = txt.replace( re, function( matching, m1, m2, m3 ) {
            var m1lc:String = m1.toLowerCase();
            g_urls[ m1lc ] = _EncodeAmpsAndAngles( m2 ); // Link IDs are case-insensitive
            if( m3 )
            {
                var txt3:String = m3;
                txt3 = txt3.replace( /"/g, "&quot;" );
                g_titles[ m1lc ] = txt3;
            }
        } );
        
        return txt;
    }
    
    internal function _HashHTMLBlocks( txt:String ):String
    {
        trace( "_HashHTMLBlocks" );
        var less_than_tab:uint = g_tab_width - 1;
        
        // Hashify HTML blocks:
        // We only want to do this for block-level HTML tags, such as headers,
        // lists, and tables. That's because we still want to wrap <p>s around
        // "paragraphs" that are wrapped in non-block-level tags, such as anchors,
        // phrase emphasis, and spans. The list of tags we're looking for is
        // hard-coded:
        var block_tags_a:String = "p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math|ins|del";
        var block_tags_b:String = "p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math";
        
    	// First, look for nested blocks, e.g.:
    	// 	<div>
    	// 		<div>
    	// 		tags for inner block must be indented.
    	// 		</div>
    	// 	</div>
    	//
    	// The outermost tags must start at the left margin for this to match, and
    	// the inner nested divs must be indented.
    	// We need to do this before the next, more liberal match, because the next
    	// match will start at the first `<div>` and stop at the first `</div>`.
        var p:String = "";
            p += "(";                   // save in $1
            p += "  ^";                 // start of line  (with /m)
            p += "<("+block_tags_a+")"; // start tag = $2
            p += "\\b";                 // word break
            p += "(.*\\n)*?";           // any number of lines, minimally matching
            p += "</\\2>";              // the matching end tag
            p += "[ \\t]*";             // trailing spaces/tabs
            p += "(?=\\n+|\\Z)";        // followed by a newline or end of document
            p += ")";
        
        var re:RegExp = new RegExp( p , "gmx" );
        txt = txt.replace( re, function( matching, m1 ) {
            var key:String = elf_hex( m1 );
            //trace( "key = [" + key + "]" );
            g_html_blocks[ key ] = m1;
            return "\n\n" + key + "\n\n";
        } );
        
        // Now match more liberally, simply from `\n<tag>` to `</tag>\n`
        var p2:String = "";
            p2 += "(";                   // save in $1
            p2 += "  ^";                 // start of line  (with /m)
            p2 += "<("+block_tags_b+")"; // start tag = $2
            p2 += "\\b";                 // word break
            p2 += "(.*\\n)*?";           // any number of lines, minimally matching
            p2 += ".*</\\2>";            // the matching end tag
            p2 += "[ \\t]*";             // trailing spaces/tabs
            p2 += "(?=\\n+|\\Z)";        // followed by a newline or end of document
            p2 += ")";
            
        var re2:RegExp = new RegExp( p2, "gmx" );
        txt = txt.replace( re2, function( matching, m1 ) {
            var key:String = elf_hex( m1 );
            //trace( "key = [" + key + "]" );
            g_html_blocks[ key ] = m1;
            return "\n\n" + key + "\n\n";
        } );
        
        // Special case just for <hr />. It was easier to make a special case than
        // to make the other regex more complicated.
        var p3:String = "";
            p3 += "(?:";
            p3 += "  (?<=\\n\\n)";              // Starting after a blank line
            p3 += "  |";                        // or
            p3 += "  \\A\\n?";                  // the beginning of the doc
            p3 += ")";
            p3 += "(";                          // save in $1
            p3 += "  [ ]{0,"+less_than_tab+"}"; 
            p3 += "  <(hr)";                    // start tag = $2
            p3 += "  \\b";                      // word break
            p3 += "  ([^<>])*?";
            p3 += "  /?>";                      // the matching end tag
            p3 += "  [ \\t]*";
            p3 += "  (?=\\n{2,}|\\Z)";          // followed by a blank line or end of document
            p3 += ")";
        
        var re3:RegExp = new RegExp( p3, "gx" );
        txt = txt.replace( re3, function( matching, m1 ) {
            var key:String = elf_hex( m1 );
            //trace( "key = [" + key + "]" );
            g_html_blocks[ key ] = m1;
            return "\n\n" + key + "\n\n";
        } );
        
        // Special case for standalone HTML comments:
        var p4:String = "";
            p4 += "(?:";
            p4 += "  (?<=\\n\\n)";              // Starting after a blank line
            p4 += "  |";                        // or
            p4 += "  \\A\\n?";                  // the beginning of the doc
            p4 += ")";
            p4 += "(";                          // save in $1
            p4 += "  [ ]{0,"+less_than_tab+"}"; 
            p4 += "  (?s:";
            p4 += "    <!";
            p4 += "    (--.*?--\\s*)+";
            p4 += "    >";
            p4 += "  )";
            p4 += "  [ \\t]*";
            p4 += "  (?=\\n{2,}|\\Z)";          // followed by a blank line or end of document
            p4 += ")";
        
        var re4:RegExp = new RegExp( p4, "gx" );
        txt = txt.replace( re4, function( matching, m1 ) {
            var key:String = elf_hex( m1 );
            //trace( "key = [" + key + "]" );
            g_html_blocks[ key ] = m1;
            return "\n\n" + key + "\n\n";
        } );
        
        //g_html_blocks[ elf_hex("toto") ] = "toto";
        /*
        var m:String;
        for( m in g_html_blocks )
        {
            trace( "g_html_blocks[" + m + "] = " + g_html_blocks[m] );    
        }
        */
        
        return txt;
    }
    
    /**
     * These are all the transformations that form block-level
     * tags like paragraphs, headers, and list items.
     */ 
    internal function _RunBlockGamut( txt:String ):String
    {
        txt = _DoHeaders( txt );
        
        // Do Horizontal Rules:
        var hr:String = "\n<hr"+g_empty_element_suffix+"\n";
        txt = txt.replace( /^[ ]{0,2}([ ]?\*[ ]?){3,}[ \t]*$/gmx , hr );
        txt = txt.replace( /^[ ]{0,2}([ ]? -[ ]?){3,}[ \t]*$/gmx , hr );
        txt = txt.replace( /^[ ]{0,2}([ ]? _[ ]?){3,}[ \t]*$/gmx , hr );
        
        txt = _DoLists( txt );
        
        txt = _DoCodeBlocks( txt );
        
        txt = _DoBlockQuotes( txt );
        
        // We already ran _HashHTMLBlocks() before, in Markdown(), but that
        // was to escape raw HTML in the original Markdown source. This time,
        // we're escaping the markup we've just created, so that we don't wrap
        // <p> tags around block-level tags.
        txt = _HashHTMLBlocks( txt );
        
        txt = _FormParagraphs( txt );
        
        return txt;
    }
    
    /**
     * These are all the transformations that occur *within* block-level
     * tags like paragraphs, headers, and list items.
     */
    internal function _RunSpanGamut( txt:String ):String
    {
        txt = _DoCodeSpans( txt );
        
        txt = _EscapeSpecialChars( txt );
        
        // Process anchor and image tags. Images must come first,
        // because ![foo][f] looks like an anchor.
        txt = _DoImages( txt );
        txt = _DoAnchors( txt );
        
        // Make links out of things like `<http://example.com/>`
        // Must come after _DoAnchors(), because you can use < and >
        // delimiters in inline links like [this](<url>).
        txt = _DoAutoLinks( txt );
        
        txt = _EncodeAmpsAndAngles( txt );
        
        txt = _DoItalicsAndBold( txt );
        
        // Do hard breaks:
        var br:String = " <br"+g_empty_element_suffix+"\n";
        txt = txt.replace( / {2,}\n/g , br );
        
        return txt;
    }
    
    internal function _EscapeSpecialChars( txt:String ):String
    {
        var tokens:Array = _TokenizeHTML( txt );
        
        txt = ""; // rebuild txt from the tokens
        
        var cur_token:Array;
        for each( cur_token in tokens ) 
        {
            if( cur_token[0] == "tag" )
            {
                // Within tags, encode * and _ so they don't conflict
                // with their use in Markdown for italics and strong.
                // We're replacing each such character with its
                // corresponding MD5 checksum value; this is likely
                // overkill, but it should prevent us from colliding
                // with the escape values by accident.
                cur_token[1] = cur_token[1].replace( / \* /gx, g_escape_table["*"] );
                cur_token[1] = cur_token[1].replace( / _  /gx, g_escape_table["_"] );
                txt += cur_token[1];
            }
            else
            {
                var t:String = cur_token[1];
                    t = _EncodeBackslashEscapes( t );
                txt += t;
            }
        }
        
        return txt;
    }
    
    /**
     * Turn Markdown link shortcuts into XHTML <a> tags.
     */ 
    internal function _DoAnchors( txt:String ):String
    {
        trace( "_DoAnchors()" );
        // First, handle reference-style links: [link text] [id]
        var p:String = "";
            p += "(";                         // wrap whole match in $1
            p += "  \\[";
            p += "  ("+g_nested_brackets+")"; // link text = $2
            /*
            p += "  (";
            p += "    (?:";
            p += "    \\[[^\\]]*\\]"; // allow brackets nested one level
            p += "    |";
            p += "    [^\\[]";     // or anything else
            p += "    )*";
            p += "  )";
            */
            p += "  \\]";
            p += "";
            p += "  [ ]?";                    // one optional space
            p += "  (?:\\n[ ]*)?";            // one optional newline followed by spaces
            p += "";
            p += "  \\[";
            p += "    (.*?)";                 // id = $3
            p += "  \\]";
            p += ")";
        
        var re:RegExp = new RegExp( p, "gx" );
        txt = txt.replace( re, function( matching, m1, m2, m3 ) {
            var result:String = "";
            var whole_match:String = m1;
            var link_text:String   = m2;
            var link_id:String;
            
            if( m3 && (m3 != "") )
            {
                link_id = m3.toLowerCase();
            }
            else
            {
                link_id = link_text.toLowerCase(); // for shortcut links like [this][].
            }
            
            if( g_urls[ link_id ] )
            {
                var url:String = g_urls[ link_id ];
                    url = url.replace( / \* /gx, g_escape_table["*"] ); // We've got to encode these to avoid
                    url = url.replace( / _  /gx, g_escape_table["_"] ); // conflicting with italics/bold.
                result = "<a href=\""+url+"\"";
                if( g_titles[ link_id ] )
                {
                    var title:String = g_titles[ link_id ];
                        title = title.replace( / \* /gx, g_escape_table["*"] );
                        title = title.replace( / _  /gx, g_escape_table["_"] );
                    result += " title=\""+title+"\"";
                }
                result += ">"+link_text+"</a>";
            }
            else
            {
                result = whole_match;
            }
            //trace( "result = [" + result + "]" );
            return result;
        } );
        
        // Next, inline-style links: [link text](url "optional title")
        var p2:String = "";
            p2 += "(";                         // wrap whole match in $1
            p2 += "  \\[";
            p2 += "  ("+g_nested_brackets+")"; // link text = $2
            p2 += "  \\]";
            p2 += "  \\(";                     // literal paren
            p2 += "    [ \\t]*";
            p2 += "    <?(.*?)>?";             // href = $3
            p2 += "    [ \\t]*";
            p2 += "    (";                     // $4
            p2 += "      ([\'\"])";            // quote char = $5
            p2 += "      (.*?)";               // Title = $6
            p2 += "      \\5";                 // matching quote
            p2 += "    )?";                    // title is optional
            p2 += "  \\)";
            p2 += ")";

        var re2:RegExp = new RegExp( p2, "gx" );        
        txt = txt.replace( re2, function( matching, m1, m2, m3, m4, m5, m6 ) {
            var result:String = "";
            var whole_match:String = m1;
            var link_text:String   = m2;
            var url:String         = m3;
            var title:String       = m6;
            
            url = url.replace( / \* /gx, g_escape_table["*"] ); // We've got to encode these to avoid
            url = url.replace( / _  /gx, g_escape_table["_"] ); // conflicting with italics/bold.
            result = "<a href=\""+url+"\"";
            
            if( title && (title != "") )
            {
                title = title.replace( /"/g, "&quot;" );
                title = title.replace( / \* /gx, g_escape_table["*"] );
                title = title.replace( / _  /gx, g_escape_table["_"] );
                result += " title=\""+title+"\"";
            }
            result += ">"+link_text+"</a>";
            //trace( "result = [" + result + "]" );
            return result;
        } );
        
        return txt;
    }
    
    /**
     * Turn Markdown image shortcuts into <img> tags.
     */ 
    internal function _DoImages( txt:String ):String
    {
        // First, handle reference-style labeled images: ![alt text][id]
        var p:String = "";
            p += "(";              // wrap whole match in $1
            p += "  !\\[";
            p += "    (.*?)";      // alt text = $2
            p += "  \\]";
            p += "";
            p += "  [ ]?";         // one optional space
            p += "  (?:\\n[ ]*)?"; // one optional newline followed by spaces
            p += "";
            p += "  \\[";
            p += "    (.*?)";      // id = $3
            p += "  \\]";
            p += ")";
            
        var re:RegExp = new RegExp( p, "gx" );
        txt = txt.replace( re, function( matching, m1, m2, m3 ) {
            var result:String = "";
            var whole_match:String = m1;
            var alt_text:String    = m2;
            var link_id:String;
            
            if( m3 && (m3 != "") )
            {
                link_id = m3.toLowerCase();
            }
            else
            {
                link_id = alt_text.toLowerCase(); // for shortcut links like ![this][].
            }
            
            alt_text = alt_text.replace( /"/g, "&quot;" );
            if( g_urls[ link_id ] )
            {
                var url:String = g_urls[ link_id ];
                    url = url.replace( / \* /gx, g_escape_table["*"] ); // We've got to encode these to avoid
                    url = url.replace( / _  /gx, g_escape_table["_"] ); // conflicting with italics/bold.
                result = "<img src=\""+url+"\" alt=\""+alt_text+"\"";
                if( g_titles[ link_id ] )
                {
                    var title:String = g_titles[ link_id ];
                        title = title.replace( / \* /gx, g_escape_table["*"] );
                        title = title.replace( / _  /gx, g_escape_table["_"] );
                    result += " title=\""+title+"\"";
                
                }
                result += g_empty_element_suffix;
            }
            else
            {
                // If there's no such link ID, leave intact:
                result = whole_match;
            }
            //trace( "result = [" + result + "]" );
            return result;
        } );
        
        // Next, handle inline images:  ![alt text](url "optional title")
        // Don't forget: encode * and _
        var p2:String = "";
            p2 += "(";               // wrap whole match in $1
            p2 += "  !\\[";
            p2 += "    (.*?)";       // alt text = $2
            p2 += "  \\]";
            p2 += "  \\(";           // literal paren
            p2 += "    [ \\t]*";
            p2 += "    <?(\\S+?)>?"; // src url = $3
            p2 += "    [ \\t]*";
            p2 += "    (";           // $4
            p2 += "      ([\'\"])";  // quote char = $5
            p2 += "      (.*?)";     // title = $6
            p2 += "      \\5";       // matching quote
            p2 += "      [ \\t]*";
            p2 += "    )?";          // title is optional
            p2 += "  \\)";
            p2 += ")";
        
        var re2:RegExp = new RegExp( p2, "gx" );
        txt = txt.replace( re2, function( matching, m1, m2, m3, m4, m5, m6 ) {
            var result:String = "";
            var whole_match:String = m1;
            var alt_text:String   = m2;
            var url:String         = m3;
            var title:String       = "";
            if( m6 && (m6 != "") )
            {
                title = m6;
            }
            
            alt_text = alt_text.replace( /"/g, "&quot;" );
            title    = title.replace( /"/g, "&quot;" );
            url = url.replace( / \* /gx, g_escape_table["*"] ); // We've got to encode these to avoid
            url = url.replace( / _  /gx, g_escape_table["_"] ); // conflicting with italics/bold.
            result = "<img src=\""+url+"\" alt=\""+alt_text+"\"";
            if( title )
            {
                title = title.replace( / \* /gx, g_escape_table["*"] );
                title = title.replace( / _  /gx, g_escape_table["_"] );
                result += " title=\""+title+"\"";
            }
            result += g_empty_element_suffix;
            //trace( "result = [" + result + "]" );
            return result;
        } );
        
        return txt;
    }
    
    internal function _DoHeaders( txt:String ):String
    {
        trace( "_DoHeaders()" );
    	// Setext-style headers:
    	//	  Header 1
    	//	  ========
    	//  
    	//	  Header 2
    	//	  --------
    	//
        txt = txt.replace( / ^(.+)[ \t]*\n=+[ \t]*\n+ /gmx , function( matching, m1 ) {
            return "<h1>" + _RunSpanGamut( m1 ) + "</h1>\n\n";
        } );
        
        txt = txt.replace( / ^(.+)[ \t]*\n-+[ \t]*\n+ /gmx , function( matching, m1 ) {
            return "<h2>" + _RunSpanGamut( m1 ) + "</h2>\n\n";
        } );
        
    	// atx-style headers:
    	//	# Header 1
    	//	## Header 2
    	//	## Header 2 with closing hashes ##
    	//	...
    	//	###### Header 6
    	//
        var p:String = "";
            p += "^(\\#{1,6})"; // $1 = string of #'s
            p += "[ \\t]*";
            p += "(.+?)";       // $2 = Header text
            p += "[ \\t]*";
            p += "\\#*";         // optional closing #'s (not counted)
            p += "\\n+";
        
        var re:RegExp = new RegExp( p, "gmx" );
        txt = txt.replace( re, function( matching, m1, m2 ) {
            var h_level:uint = m1.length;
            //trace( "h_level = " + h_level );
            //var tmp_h:String = "<h"+h_level+">" + _RunSpanGamut( m2 ) + "</h"+h_level+">\n\n";
            //trace( "tmp_h = " + tmp_h );
            return "<h"+h_level+">" + _RunSpanGamut( m2 ) + "</h"+h_level+">\n\n";
            //return tmp_h;
        } );
        
        return txt;
    }
    
    /**
     * Form HTML ordered (numbered) and unordered (bulleted) lists.
     */ 
    internal function _DoLists( txt:String ):String
    {
        var less_than_tab:uint = g_tab_width - 1;
        
        // Re-usable patterns to match list item bullets and number markers:
        var marker_ul:String  = "[*+-]";
        var marker_ol:String  = "\\d+[.]";
        var marker_any:String = "(?:"+marker_ul+"|"+marker_ol+")";
        
        // Re-usable pattern to match any entirel ul or ol list:
        var p:String = "";
            p += "(";                         // $1 = whole list
            p += "  (";                       // $2
            p += "    [ ]{0,"+less_than_tab+"}"; // 
            p += "    ("+marker_any+")";       // $3 = first list item marker
            p += "    [ \\t]+";
            p += "  )";
            p += "  (?s:.+?)";
            p += "  (";                       // $4
            p += "    \\z";
            p += "    |";
            p += "    \\n{2,}";
            p += "    (?=\\S)";
            p += "    (?!";                   // Negative lookahead for another list item marker
            p += "      [ \\t]*";
            p += "      "+marker_any+"[ \\t]+";
            p += "    )";
            p += "  )";
            p += ")";
        
    	// We use a different prefix before nested lists than top-level lists.
    	// See extended comment in _ProcessListItems().
    	//
    	// Note: There's a bit of duplication here. My original implementation
    	// created a scalar regex pattern as the conditional result of the test on
    	// $g_list_level, and then only ran the $text =~ s{...}{...}egmx
    	// substitution once, using the scalar as the pattern. This worked,
    	// everywhere except when running under MT on my hosting account at Pair
    	// Networks. There, this caused all rebuilds to be killed by the reaper (or
    	// perhaps they crashed, but that seems incredibly unlikely given that the
    	// same script on the same server ran fine *except* under MT. I've spent
    	// more time trying to figure out why this is happening than I'd like to
    	// admit. My only guess, backed up by the fact that this workaround works,
    	// is that Perl optimizes the substition when it can figure out that the
    	// pattern will never change, and when this optimization isn't on, we run
    	// afoul of the reaper. Thus, the slightly redundant code to that uses two
    	// static s/// patterns rather than one conditional pattern.
        if( g_list_level )
        {
            var re:RegExp = new RegExp( "^" + p, "gmx" );
            txt = txt.replace( re, function( matching, m1, m2, m3 ) {
                var list:String = m1;
                var list_type:String;
                var re_ul:RegExp = new RegExp( marker_ul, "m" );
                list_type = re_ul.test( m3 ) ? "ul" : "ol";
                
                // Turn double returns into triple returns, so that we can make a
                // paragraph for the last item in a list, if necessary:
                list = list.replace( /\n{2,}/g , "\n\n\n" );
                var result:String = _ProcessListItems( list, marker_any );
                    result = "<"+list_type+">\n" + result + "</"+list_type+">\n";
                return result;
            } );
        }
        else
        {
            var re2:RegExp = new RegExp( "(?:(?<=\\n\\n)|\\A\\n?)" + p, "gmx" );
            txt = txt.replace( re2, function( matching, m1, m2, m3 ) {
                var list:String = m1;
                var list_type:String;
                var re_ul:RegExp = new RegExp( marker_ul, "m" );
                list_type = re_ul.test( m3 ) ? "ul" : "ol";
                
                // Turn double returns into triple returns, so that we can make a
                // paragraph for the last item in a list, if necessary:
                list = list.replace( /\n{2,}/g , "\n\n\n" );
                var result:String = _ProcessListItems( list, marker_any );
                    result = "<"+list_type+">\n" + result + "</"+list_type+">\n";
                return result;
            } );
        }
        
        return txt;
    }
    
    /**
     * Process the contents of a single ordered or unordered list, splitting it
     * into individual list items.
     */
    internal function _ProcessListItems( list_str:String, marker_any:String ):String
    {
    	// The $g_list_level global keeps track of when we're inside a list.
    	// Each time we enter a list, we increment it; when we leave a list,
    	// we decrement. If it's zero, we're not in a list anymore.
    	//
    	// We do this because when we're not inside a list, we want to treat
    	// something like this:
    	//
    	//		I recommend upgrading to version
    	//		8. Oops, now this line is treated
    	//		as a sub-list.
    	//
    	// As a single paragraph, despite the fact that the second line starts
    	// with a digit-period-space sequence.
    	//
    	// Whereas when we're inside a list (or sub-list), that line will be
    	// treated as the start of a sub-list. What a kludge, huh? This is
    	// an aspect of Markdown's syntax that's hard to parse perfectly
    	// without resorting to mind-reading. Perhaps the solution is to
    	// change the syntax rules such that sub-lists must start with a
    	// starting cardinal number; e.g. "1." or "a.".
        g_list_level++;
        
        // trim trailing blank lines:
        list_str = list_str.replace( /\n{2,}\z/ , "\n" );
        
        var p:String = "";
            p += "(\\n)?";                                  // leading line = $1
            p += "(^[ \\t]*)";                              // leading whitespace = $2
            p += "("+marker_any+") [ \\t]+";                // list marker = $3
            p += "((?s:.+?)";                               // list item text   = $4
            p += "(\\n{1,2}))";
            p += "(?= \\n* (\\z | \\2 ("+marker_any+") [ \\t]+))";
        
        var re:RegExp = new RegExp( p , "gmx" );
        list_str = list_str.replace( re, function( matching, m1, m2, m3, m4 ) {
            var item:String = m4;
            var leading_line:* = m1;
            var leading_space:String = m2;
            
            var re2:RegExp = new RegExp( /\n{2,}/ );
            if( leading_line || re2.test( item ) )
            {
                item = _RunBlockGamut( _Outdent( item ) );
            }
            else
            {
                // Recursion for sub-lists:
                item = _DoLists( _Outdent( item ) );
                item - item.replace( /(\n|\r)+$/ , "" ); //chomp
                item = _RunSpanGamut( item );
            }
            
            return "<li>" + item + "</li>\n";
        } );
        
        g_list_level--;
        return list_str;
    }
    
    /**
     * Process Markdown `<pre><code>` blocks.
     */
    internal function _DoCodeBlocks( txt:String ):String
    {
        var p:String = "";
            p += "(?:\\n\\n|\\A)";
            p += "(";                // $1 = the code block -- one or more lines, starting with a space/tab
            p += "  (?:";
            p += "    (?:[ ]{"+g_tab_width+"} | \\t)";  // Lines must start with a tab or a tab-width of spaces
            p += "    .*\\n+";
            p += "  )+";
            p += ")";
            p += "((?=^[ ]{0,"+g_tab_width+"}\\S)|\\Z)"; // Lookahead for non-space at line-start, or end of doc

        var re:RegExp = new RegExp( p, "gmx" );
        txt = txt.replace( re, function( matching, m1 ) {
            var codeblock:String = m1;
            var result:String = ""; // return value
            codeblock = _EncodeCode( _Outdent( codeblock ) );
            codeblock = _Detab( codeblock );
            codeblock = codeblock.replace( /\A\n+/ , "" ); // trim leading newlines
            codeblock = codeblock.replace( /\s+\z/ , "" ); // trim trailing whitespace
            
            result = "\n\n<pre><code>" + codeblock + "\n</code></pre>\n\n";
            return result;
        } );
        
        return txt;
    }
    
    internal function _DoCodeSpans( txt:String ):String
    {
        //
        // 	*	Backtick quotes are used for <code></code> spans.
        // 
        // 	*	You can use multiple backticks as the delimiters if you want to
        // 		include literal backticks in the code span. So, this input:
        //     
        //         Just type ``foo `bar` baz`` at the prompt.
        //     
        //     	Will translate to:
        //     
        //         <p>Just type <code>foo `bar` baz</code> at the prompt.</p>
        //     
        //		There's no arbitrary limit to the number of backticks you
        //		can use as delimters. If you need three consecutive backticks
        //		in your code, use four for delimiters, etc.
        //
        //	*	You can use spaces to get literal backticks at the edges:
        //     
        //         ... type `` `bar` `` ...
        //     
        //     	Turns to:
        //     
        //         ... type <code>`bar`</code> ...
        //
        var p:String = "";
            p += "(`+)";   // $1 = Opening run of `
            p += "(.+?)";  // $2 = The code block
            p += "(?<!`)";
            p += "\\1";     // Matching closer
            p += "(?!`)";
        
        var re:RegExp = new RegExp( p, "gx" );
        txt = txt.replace( re, function( matching, m1, m2 ) {
            var c:String = m2;
                c = c.replace( /^[ \t]*/g , "" ); // leading whitespace
                c = c.replace( /[ \t]*$/g , "" ); // trailing whitespace
                c = _EncodeCode( c );
            
            return "<code>"+c+"</code>";
        } );
        
        return txt;
    }
    
    /**
     * Encode/escape certain characters inside Markdown code runs.
     * The point is that in code, these characters are literals,
     * and lose their special Markdown meanings.
     */
    internal function _EncodeCode( txt:String ):String
    {
    	// Encode all ampersands; HTML entities are not
    	// entities within a Markdown code span.
        txt = txt.replace( /&/g , "&amp;" );
        
    	// Encode $'s, but only if we're running under Blosxom.
    	// (Blosxom interpolates Perl variables in article bodies.)
        //if( g_blosxom )
        //{
        //    txt = txt.replace( /\$/g , "&#036;" );
        //}
        
        // Do the angle bracket song and dance:
        txt = txt.replace( / < /gx , "&lt;" );
        txt = txt.replace( / > /gx , "&gt;" );
        
        // Now, escape characters that are magic in Markdown:
        txt = txt.replace( / \* /gx, g_escape_table["*"] );
        txt = txt.replace( / _  /gx, g_escape_table["_"] );
        txt = txt.replace( / {  /gx, g_escape_table["{"] );
        txt = txt.replace( / }  /gx, g_escape_table["}"] );
        txt = txt.replace( / [  /gx, g_escape_table["["] );
        txt = txt.replace( / ]  /gx, g_escape_table["]"] );
        txt = txt.replace( / \\ /gx, g_escape_table["\\"] );
        
        return txt;
    }
    
    internal function _DoItalicsAndBold( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _DoBlockQuotes( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _FormParagraphs( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _EncodeAmpsAndAngles( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _EncodeBackslashEscapes( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _DoAutoLinks( txt:String ):String
    {
        
        
        return txt;
    }
    
    internal function _EncodeEmailAddress( txt:String ):String
    {
        
        
        return txt;
    }
    
    /**
     * Swap back in all the special characters we've hidden.
     */
    internal function _UnescapeSpecialChars( txt:String ):String
    {
        var chars:String;
        var hash:String;
        var re:RegExp;
        for( chars in g_escape_table )
        {
            hash = g_escape_table[ chars ];
            re = new RegExp( hash, "g" );
            txt = txt.replace( re, chars );
        }
        
        return txt;
    }
    
    /* Note:
       in AS3 we return directly the array, not a reference.
       
       structure is basically a 2 dimension array
       tokens[ i ] = [ "tag" ][ value ];
       tokens[ i ] = [ "text" ][ value ];
       etc.
    */
    /**
     * 
     * @param  str String containing HTML markup.
     * @return Reference to an array of the tokens comprising the input
     *         string. Each token is either a tag (possibly with nested,
     *         tags contained therein, such as <a href="<MTFoo>">, or a
     *         run of text between tags. Each element of the array is a
     *         two-element array; the first is either 'tag' or 'text';
     *         the second is the actual value.
     * @see Derived from the _tokenize() subroutine from Brad Choate's MTRegex plugin. http://www.bradchoate.com/past/mtregex.php
     */ 
    internal function _TokenizeHTML( str:String ):Array
    {
        var pos:int  = 0;
        var len:uint = str.length;
        var tokens:Array = [];
        
        // my $nested_tags = join('|', ('(?:<[a-z/!$](?:[^<>]') x $depth) . (')*>)' x  $depth);
        var depth:uint = 6;
        var nested_tags:String = "";
        var tag_s:Array = [];
        var tag_e:String = "";
        var tmp:Array = new Array( depth );
            tmp.forEach( function() {
                tag_s.push( "(?:<[a-z/!$](?:[^<>]" );
                tag_e += ")*>)";
            } );
        nested_tags = tag_s.join( "|" ) + tag_e;
        
        var p:String = "";
            p += "(";
            p += "(?s: <! ( -- .*? -- \\s* )+ > ) | "; // comment
            p += "(?s: <\\? .*? \\?> ) | ";            // processing instruction
            p += nested_tags;                          // nested tags
            p += ")";
        
        var re:RegExp = new RegExp( p, "gix" );
        var match:*;
        while( match = re.exec( str )  )
        {
            var whole_tag:String = match[1];
            var sec_start:int   = re.lastIndex;
            var tag_start:int   = sec_start - whole_tag.length;
            if( pos < tag_start )
            {
                tokens.push( ["text", str.substr( pos, tag_start - pos ) ] );
            }
            tokens.push( [ "tag", whole_tag ] );
            pos = re.lastIndex;
        }
        
        if( pos < len )
        {
            tokens.push( ["text", str.substr( pos, len - pos ) ] );
        }
        
        return tokens;
    }
    
    /**
     * Remove one level of line-leading tabs or spaces
     */
    internal function _Outdent( txt:String ):String
    {
        var p:String = "^(\\t|[ ]{1,"+g_tab_width+"})";
        var re:RegExp = new RegExp( p, "gm" );
        txt = txt.replace( re , "" );
        
        return txt;
    }
    
    internal function _Detab( txt:String ):String
    {
        // Cribbed from a post by Bart Lateur:
        // <http://www.nntp.perl.org/group/perl.macperl.anyperl/154>
        // $text =~ s{(.*?)\t}{$1.(' ' x ($g_tab_width - length($1) % $g_tab_width))}ge;
        
        /* Note:
           s///e wraps an eval{...} around the replacement string
           in AS3 we don't have evsal() on regexp but we can use a
           function that does the equivalent job as 2nd arg of replace
           
           for the part: ' ' x num_of_spaces
           we can use any for...loop but decided to go
           with the 'trick' array 'num of element' forEach
           eg. new Array(n) create n elements
        */
        txt = txt.replace( /(.*?)\t/g, function( matching, m1, m2 ) {
            var spc:Number = g_tab_width - (m1.length % g_tab_width);
            var spaces:String = "";
            //trace( "spc = " + spc );
            var tmp:Array = new Array( spc );
                tmp.forEach( function() { spaces += " " } );
            //trace( "spaces = [" + spaces + "]" );
            return m1 + spaces;
        });
        
        return txt;
    }
    
    
}