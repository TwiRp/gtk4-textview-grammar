/**
 * MIT License
 *
 * Copyright (c) 2022 TwiRpin Around
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

namespace TwiRpin {
    public class Markdown {
        // Views to attach to
        private unowned GtkSource.View view;
        private unowned GtkSource.Buffer buffer;

        // How often to scan text for changes
        private TimedMutex update_limits;

        // Copy of TextBuffer data and mutex to access copy
        private Mutex checking;
        private string checking_copy;

        // Internal state
        private bool active_selection = false;
        private bool cursor_at_interesting_location = false;
        private int last_cursor;
        private int copy_offset;
        private int hashtag_w;
        private int space_w;
        private int avg_w;

        // Regexes
        private Regex is_list;
        private Regex is_partial_list;
        private Regex numerical_list;
        private Regex is_url;
        private Regex is_markdown_url;
        private Regex is_heading;
        private Regex is_codeblock;

        // TextTags
        private Gtk.TextTag[] heading_text;
        public Gtk.TextTag code_block;
        public Gtk.TextTag markdown_link;
        public Gtk.TextTag markdown_url;

        /**
         * Markdown object for formatting and suggestions
         */
        public Markdown () {
            try {
                is_heading = new Regex ("(?:^|\\n)(#+\\s[^\\n\\r]+?)(?:$|\\r?\\n)", RegexCompileFlags.BSR_ANYCRLF | RegexCompileFlags.NEWLINE_ANYCRLF | RegexCompileFlags.CASELESS, 0);
                is_list = new Regex ("^(\\s*([\\*\\-\\+\\>]|[0-9]+(\\.|\\)))\\s)\\s*(.+)", RegexCompileFlags.CASELESS, 0);
                is_partial_list = new Regex ("^(\\s*([\\*\\-\\+\\>]|[0-9]+\\.))\\s+$", RegexCompileFlags.CASELESS, 0);
                numerical_list = new Regex ("^(\\s*)([0-9]+)((\\.|\\))\\s+)$", RegexCompileFlags.CASELESS, 0);
                is_url = new Regex ("^(http|ftp|ssh|mailto|tor|torrent|vscode|atom|rss|file)?s?(:\\/\\/)?(www\\.)?([a-zA-Z0-9\\.\\-]+)\\.([a-z]+)([^\\s]+)$", RegexCompileFlags.CASELESS, 0);
                is_codeblock = new Regex ("(```[a-zA-Z]*[\\n\\r]((.*?)[\\n\\R])*?```[\\n\\r])", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
                is_markdown_url = new Regex ("(?<text_group>\\[(?>[^\\[\\]]+|(?&text_group))+\\])(?:\\((?<url>\\S+?)(?:[ ]\"(?<title>(?:[^\"]|(?<=\\\\)\")*?)\")?\\))", RegexCompileFlags.CASELESS, 0);
            } catch (Error e) {
                warning ("Could not initialize regexes: %s", e.message);
            }
            checking = Mutex ();
            update_limits = new TimedMutex (250);
            active_selection = false;
            last_cursor = -1;
        }

        /**
         * Attaches to a GtkSource.View to provide special markdown functionality
         */
        public bool attach (GtkSource.View textview) {
            if (textview == null) {
                return false;
            }

            view = textview;
            buffer = (GtkSource.Buffer) textview.get_buffer ();

            if (buffer == null) {
                view = null;
                return false;
            }

            view.destroy.connect (detach);

            heading_text = new Gtk.TextTag[6];
            for (int h = 0; h < 6; h++) {
                heading_text[h] = buffer.create_tag ("heading%d-text".printf (h + 1));
            }

            code_block = buffer.create_tag ("code-block");
            markdown_link = buffer.create_tag ("markdown-link");
            markdown_url = buffer.create_tag ("markdown-url");
            markdown_url.invisible = true;
            markdown_url.invisible_set = true;
            cursor_at_interesting_location = false;
            active_selection = false;

            buffer.cursor_moved.connect (cursor_update_heading_margins);

            last_cursor = -1;

            return true;
        }

        public void detach () {
            if (buffer == null) {
                return;
            }

            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);

            buffer.remove_tag (code_block, start, end);
            buffer.remove_tag (markdown_link, start, end);
            buffer.remove_tag (markdown_url, start, end);
            for (int h = 0; h < 6; h++) {
                buffer.remove_tag (heading_text[h], start, end);
                buffer.tag_table.remove (heading_text[h]);
            }
            buffer.tag_table.remove (code_block);
            buffer.tag_table.remove (markdown_link);
            buffer.tag_table.remove (markdown_url);
            code_block = null;
            markdown_link = null;
            markdown_url = null;
            cursor_at_interesting_location = false;
            active_selection = false;

            buffer.cursor_moved.disconnect (cursor_update_heading_margins);
            view.destroy.disconnect (detach);
            view = null;
            buffer = null;
            last_cursor = -1;
        }

        public void reset () {
            last_cursor = -1;
            recheck_all ();
        }

        public void recheck_all () {
            if (view == null || buffer == null) {
                return;
            }

            recalculate_margins ();

            if (!buffer.has_selection) {
                if (!update_limits.can_do_action ()) {
                    return;
                }
            }

            if (!checking.trylock ()) {
                return;
            }

            var style_scheme = buffer.get_style_scheme ();
            bool background_set = false;
            code_block.background_full_height = true;
            code_block.background_full_height_set = true;
            if (style_scheme != null) {
                var style = style_scheme.get_style ("def:preformatted-section");
                if (style != null) {
                    if (style.background_set) {
                        Gdk.RGBA bgc = Gdk.RGBA ();
                        if (bgc.parse (style.background)) {
                            code_block.background_rgba = bgc;
                            code_block.background_set = true;
                            code_block.paragraph_background_rgba = bgc;
                            code_block.paragraph_background_set = true;
                            background_set = true;
                        }
                    }
                }
            }
            code_block.background_set = background_set;
            code_block.paragraph_background_set = background_set;

            if (active_selection) {
                markdown_link.weight = Pango.Weight.NORMAL;
                markdown_link.weight_set = true;
                markdown_url.weight = Pango.Weight.NORMAL;
                markdown_url.weight_set = true;
            } else {
                markdown_link.weight_set = false;
                markdown_url.weight_set = false;
            }

            // Remove any previous tags
            Gtk.TextIter start, end, cursor_iter;
            var cursor = buffer.get_insert ();
            buffer.get_iter_at_mark (out cursor_iter, cursor);
            int current_cursor = cursor_iter.get_offset ();

            tag_code_blocks ();
            if (last_cursor == -1) {
                buffer.get_bounds (out start, out end);
                run_between_start_and_end (start, end);
            } else {
                //
                // Scan where we are
                //
                buffer.get_iter_at_mark (out start, cursor);
                buffer.get_iter_at_mark (out end, cursor);
                get_chunk_of_text_around_cursor (ref start, ref end, true);
                run_between_start_and_end (start, end);

                //
                // Rescan where we were if still in buffer,
                // and not where we just scanned
                //
                if ((current_cursor - last_cursor).abs () > 60) {
                    Gtk.TextIter old_start, old_end, bound_start, bound_end;
                    buffer.get_bounds (out bound_start, out bound_end);
                    buffer.get_iter_at_offset (out old_start, last_cursor);
                    buffer.get_iter_at_offset (out old_end, last_cursor);
                    if (old_start.in_range (bound_start, bound_end)) {
                        get_chunk_of_text_around_cursor (ref old_start, ref old_end, true);
                        if (!old_start.in_range (start, end) || !old_end.in_range (start, end)) {
                            run_between_start_and_end (old_start, old_end);
                        }
                    }
                }
            }

            last_cursor = current_cursor;
            checking.unlock ();
        }

        private void run_between_start_and_end (Gtk.TextIter start, Gtk.TextIter end) {
            copy_offset = start.get_offset ();
            checking_copy = buffer.get_text (start, end, true);

            update_heading_margins (start, end);
            update_link_text (start, end);

            checking_copy = "";
        }

        private void cursor_update_heading_margins () {
            var cursor = buffer.get_insert ();
            Gtk.TextIter cursor_location;
            buffer.get_iter_at_mark (out cursor_location, cursor);
            if (cursor_location.has_tag (markdown_link) || cursor_location.has_tag (markdown_url) || buffer.has_selection) {
                recheck_all ();
                cursor_at_interesting_location = true;
            } else if (cursor_at_interesting_location) {
                recheck_all ();
                Gtk.TextIter before, after;
                Gtk.TextIter bound_start, bound_end;
                buffer.get_bounds (out bound_start, out bound_end);
                buffer.get_iter_at_mark (out before, cursor);
                buffer.get_iter_at_mark (out after, cursor);
                if (!before.backward_line()) {
                    before = bound_start;
                }
                if (!after.forward_line ()) {
                    after = bound_end;
                }
                string sample_text = buffer.get_text (before, after, true);
                // Keep interesting location if we're potentially in something we can remove a link to.
                if (!is_markdown_url.match (sample_text, RegexMatchFlags.BSR_ANYCRLF | RegexMatchFlags.NEWLINE_ANYCRLF)) {
                    cursor_at_interesting_location = false;
                }
            }
        }

        private void update_heading_margins (Gtk.TextIter start_region, Gtk.TextIter end_region) {
            try {
                Gtk.TextIter start, end;
                Gtk.TextIter cursor_location;
                var cursor = buffer.get_insert ();
                MatchInfo match_info;
                buffer.get_iter_at_mark (out cursor_location, cursor);

                for (int h = 0; h < 6; h++) {
                    buffer.remove_tag (heading_text[h], start_region, end_region);
                }

                buffer.tag_table.foreach ((tag) => {
                    if (tag.name != null && tag.name.has_prefix ("list-")) {
                        buffer.remove_tag (tag, start_region, end_region);
                    }
                });

                // Tag headings and make sure they're not in code blocks
                if (is_heading.match_full (checking_copy, checking_copy.length, 0, RegexMatchFlags.BSR_ANYCRLF | RegexMatchFlags.NEWLINE_ANYCRLF, out match_info)) {
                    do {
                        int start_pos, end_pos;
                        string heading = match_info.fetch (1);
                        bool headify = match_info.fetch_pos (1, out start_pos, out end_pos) && (heading.index_of ("\n") < 0);
                        if (headify) {
                            start_pos = copy_offset + checking_copy.char_count (start_pos);
                            end_pos = copy_offset + checking_copy.char_count (end_pos);
                            buffer.get_iter_at_offset (out start, start_pos);
                            buffer.get_iter_at_offset (out end, end_pos);
                            if (start.has_tag (code_block) || end.has_tag (code_block)) {
                                continue;
                            }
                            int heading_depth = heading.index_of_char (' ') - 1;
                            if (heading_depth >= 0 && heading_depth < 6) {
                                buffer.apply_tag (heading_text[heading_depth], start, end);
                            }
                        }
                    } while (match_info.next ());
                }

                // Tag lists and make sure they're not in code blocks
                Gtk.TextIter? line_start = start_region, line_end = null;
                if (!line_start.starts_line ()) {
                    line_start.backward_line ();
                }
                do {
                    while (line_start.get_char () == '\r' || line_start.get_char () == '\n') {
                        if (!line_start.forward_char ()) {
                            break;
                        }
                    }
                    line_end = line_start;
                    if (!line_end.forward_line ()) {
                        break;
                    }
                    string line = line_start.get_text (line_end);
                    if (is_list.match_full (line, line.length, 0, 0, out match_info)) {
                        string list_marker = match_info.fetch (1);
                        if (!line_start.has_tag (code_block) && !line_end.has_tag (code_block)) {
                            list_marker = list_marker.replace ("\t", "    ");
                            int list_depth = list_marker.length;
                            if (list_depth >= 0) {
                                int list_px_index = get_string_px_width (list_marker);
                                Gtk.TextTag? list_indent = buffer.tag_table.lookup ("list-" + list_px_index.to_string ());
                                if (list_indent == null) {
                                    list_indent = buffer.create_tag ("list-" + list_px_index.to_string ());
                                }
                                list_indent.left_margin = view.left_margin;
                                list_indent.left_margin_set = false;
                                list_indent.accumulative_margin = false;
                                list_indent.indent = -list_px_index;
                                list_indent.indent_set = true;
                                buffer.apply_tag (list_indent, line_start, line_end);
                            }
                        }
                    }
                    line_start = line_end;
                } while (true);
            } catch (Error e) {
                warning ("Could not adjust headers: %s", e.message);
            }
        }

        private void update_link_text (Gtk.TextIter start_region, Gtk.TextIter end_region) {
            buffer.remove_tag (markdown_link, start_region, end_region);
            buffer.remove_tag (markdown_url, start_region, end_region);

            try {
                Gtk.TextIter start, end;
                Gtk.TextIter cursor_location;
                var cursor = buffer.get_insert ();
                MatchInfo match_info;
                buffer.get_iter_at_mark (out cursor_location, cursor);
                Gtk.TextIter bound_start, bound_end;
                buffer.get_bounds (out bound_start, out bound_end);
                bool check_selection = buffer.get_has_selection ();
                Gtk.TextIter? select_start = null, select_end = null;
                if (check_selection) {
                    buffer.get_selection_bounds (out select_start, out select_end);
                }
                if (is_markdown_url.match_full (checking_copy, checking_copy.length, 0, RegexMatchFlags.BSR_ANYCRLF | RegexMatchFlags.NEWLINE_ANYCRLF, out match_info)) {
                    do {
                        buffer.get_bounds (out bound_start, out bound_end);
                        int start_link_pos, end_link_pos;
                        int start_url_pos, end_url_pos;
                        int start_full_pos, end_full_pos;
                        //  warning ("Link Found, Text: %s, URL: %s", match_info.fetch (1), match_info.fetch (2));
                        bool linkify = match_info.fetch_pos (1, out start_link_pos, out end_link_pos);
                        bool urlify = match_info.fetch_pos (2, out start_url_pos, out end_url_pos);
                        bool full_found = match_info.fetch_pos (0, out start_full_pos, out end_full_pos);
                        if (linkify && urlify && full_found) {
                            start_full_pos = copy_offset + checking_copy.char_count (start_full_pos);
                            end_full_pos = copy_offset + checking_copy.char_count (end_full_pos);
                            //
                            // Don't hide active link's where the cursor is present
                            //
                            buffer.get_iter_at_offset (out start, start_full_pos);
                            buffer.get_iter_at_offset (out end, end_full_pos);

                            if (cursor_location.in_range (start, end)) {
                                buffer.apply_tag (markdown_link, start, end);
                                continue;
                            }

                            if (check_selection) {
                                if (start.in_range (select_start, select_end) || end.in_range (select_start, select_end)) {
                                    buffer.apply_tag (markdown_link, start, end);
                                    continue;
                                }
                            }

                            // Check if we're in inline code
                            if (start.backward_line ()) {
                                buffer.get_iter_at_offset (out end, start_full_pos);
                                if (start.in_range (bound_start, bound_end) && end.in_range (bound_start, bound_end)) {
                                    string sanity_check = buffer.get_text (start, end, true);
                                    if (sanity_check.index_of_char ('`') >= 0) {
                                        buffer.get_iter_at_offset (out end, end_full_pos);
                                        if (end.forward_line ()) {
                                            buffer.get_iter_at_offset (out start, end_full_pos);
                                            sanity_check = buffer.get_text (start, end, true);
                                            if (sanity_check.index_of_char ('`') >= 0) {
                                                continue;
                                            }
                                        }
                                    }
                                } else {
                                    // Bail, our calculations are now out of range
                                    continue;
                                }
                            }

                            //
                            // Link Text [Text]
                            //
                            start_link_pos = copy_offset + checking_copy.char_count (start_link_pos);
                            end_link_pos = copy_offset + checking_copy.char_count (end_link_pos);
                            buffer.get_iter_at_offset (out start, start_link_pos);
                            buffer.get_iter_at_offset (out end, end_link_pos);
                            if (start.has_tag (code_block) || end.has_tag (code_block)) {
                                continue;
                            }
                            if (start.in_range (bound_start, bound_end) && end.in_range (bound_start, bound_end)) {
                                buffer.apply_tag (markdown_link, start, end);
                            } else  {
                                // Bail, our calculations are now out of range
                                continue;
                            }

                            //
                            // Starting [
                            //
                            buffer.get_iter_at_offset (out start, start_link_pos);
                            buffer.get_iter_at_offset (out end, start_link_pos);
                            bool not_at_start = start.backward_chars (1);
                            end.forward_char ();
                            if (start.in_range (bound_start, bound_end) && end.in_range (bound_start, bound_end)) {
                                if (start.get_char () != '!') {
                                    if (not_at_start) {
                                        start.forward_char ();
                                    }
                                    buffer.apply_tag (markdown_url, start, end);
                                    //
                                    // Closing ]
                                    //
                                    buffer.get_iter_at_offset (out start, end_link_pos);
                                    buffer.get_iter_at_offset (out end, end_link_pos);
                                    start.backward_char ();
                                    buffer.apply_tag (markdown_url, start, end);
                                }
                            } else {
                                // Bail, our calculations are now out of range
                                continue;
                            }

                            //
                            // Link URL (https://twirp.in)
                            //
                            start_url_pos = copy_offset + checking_copy.char_count (start_url_pos);
                            buffer.get_iter_at_offset (out start, start_url_pos);
                            start.backward_char ();
                            buffer.get_iter_at_offset (out end, end_full_pos);
                            if (start.has_tag (code_block) || end.has_tag (code_block)) {
                                continue;
                            }
                            if (start.in_range (bound_start, bound_end) && end.in_range (bound_start, bound_end)) {
                                buffer.apply_tag (markdown_url, start, end);
                            } else  {
                                // Bail, our calculations are now out of range
                                continue;
                            }
                        }
                    } while (match_info.next ());
                }
            } catch (Error e) {
                warning ("Could not apply link formatting: %s", e.message);
            }
        }

        private void tag_code_blocks () {
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            buffer.remove_tag (code_block, start, end);
            string code_block_copy = buffer.get_text (start, end, true);
            // Tag code blocks as such (regex hits issues on large text)
            int block_occurrences = code_block_copy.down ().split ("\n```").length - 1;
            if (block_occurrences % 2 == 0) {
                int offset = code_block_copy.index_of ("\n```");
                while (offset > 0) {
                    offset = offset + 1;
                    int next_offset = code_block_copy.index_of ("\n```", offset + 1);
                    if (next_offset > 0) {
                        int start_pos, end_pos;
                        start_pos = code_block_copy.char_count (offset);
                        end_pos = code_block_copy.char_count ((next_offset + 4));
                        buffer.get_iter_at_offset (out start, start_pos);
                        buffer.get_iter_at_offset (out end, end_pos);
                        buffer.apply_tag (code_block, start, end);
                        //
                        // Remove links and headings from codeblock.
                        //
                        for (int h = 0; h < 6; h++) {
                            buffer.remove_tag (heading_text[h], start, end);
                        }
                        buffer.remove_tag (markdown_link, start, end);
                        buffer.remove_tag (markdown_url, start, end);
                        offset = code_block_copy.index_of ("\n```", next_offset + 1);
                    } else {
                        break;
                    }
                }
            }
        }

        private int get_string_px_width (string str) {
            int f_w = 14;
            if (view.get_realized ()) {
                var font_context = view.get_pango_context ();
                var font_desc = font_context.get_font_description ();
                var font_layout = new Pango.Layout (font_context);
                font_layout.set_font_description (font_desc);
                font_layout.set_text (str, str.length);
                Pango.Rectangle ink, logical;
                font_layout.get_pixel_extents (out ink, out logical);
                font_layout.dispose ();
                debug ("# Ink: %d, Logical: %d", ink.width, logical.width);
                return int.max (ink.width, logical.width);
            }
            return f_w;
        }

        private void recalculate_margins () {
            int m = view.left_margin;
            int f_w = 14;
            hashtag_w = 14;
            space_w = 14;
            avg_w = 14;

            if (view.get_realized ()) {
                var font_context = view.get_pango_context ();
                var font_desc = font_context.get_font_description ();
                var font_layout = new Pango.Layout (font_context);
                font_layout.set_font_description (font_desc);
                font_layout.set_text ("#", 1);
                Pango.Rectangle ink, logical;
                font_layout.get_pixel_extents (out ink, out logical);
                debug ("# Ink: %d, Logical: %d", ink.width, logical.width);
                hashtag_w = int.max (ink.width, logical.width);
                font_layout.set_text (" ", 1);
                font_layout.get_pixel_extents (out ink, out logical);
                font_layout.dispose ();
                debug ("  Ink: %d, Logical: %d", ink.width, logical.width);
                space_w = int.max (ink.width, logical.width);
                if (space_w + hashtag_w <= 0) {
                    hashtag_w = f_w;
                    space_w = f_w;
                }
                if (space_w < (hashtag_w / 2)) {
                    avg_w = (int)((hashtag_w + hashtag_w + space_w) / 3.0);
                } else {
                    avg_w = (int)((hashtag_w + space_w) / 2.0);
                }
                debug ("%s Hashtag: %d, Space: %d, AvgChar: %d", font_desc.get_family (), hashtag_w, space_w, avg_w);
                if (view.left_margin <  ((hashtag_w * 10) + space_w)) {
                    view.left_margin = ((hashtag_w * 10) + space_w);
                }
                if (view.right_margin <  ((hashtag_w * 10) + space_w)) {
                    view.right_margin = ((hashtag_w * 10) + space_w);
                }
                m = view.left_margin;
                if (m - ((hashtag_w * 6) + space_w) <= 0) {
                    heading_text[0].left_margin = m;
                    heading_text[1].left_margin = m;
                    heading_text[2].left_margin = m;
                    heading_text[3].left_margin = m;
                    heading_text[4].left_margin = m;
                    heading_text[5].left_margin = m;
                    heading_text[0].indent_set = false;
                    heading_text[1].indent_set = false;
                    heading_text[2].indent_set = false;
                    heading_text[3].indent_set = false;
                    heading_text[4].indent_set = false;
                    heading_text[5].indent_set = false;
                } else {
                    heading_text[0].left_margin = m - ((hashtag_w * 1) + space_w);
                    heading_text[1].left_margin = m - ((hashtag_w * 2) + space_w);
                    heading_text[2].left_margin = m - ((hashtag_w * 3) + space_w);
                    heading_text[3].left_margin = m - ((hashtag_w * 4) + space_w);
                    heading_text[4].left_margin = m - ((hashtag_w * 5) + space_w);
                    heading_text[5].left_margin = m - ((hashtag_w * 6) + space_w);
                    heading_text[0].indent = -((hashtag_w * 1) + space_w);
                    heading_text[1].indent = -((hashtag_w * 2) + space_w);
                    heading_text[2].indent = -((hashtag_w * 3) + space_w);
                    heading_text[3].indent = -((hashtag_w * 4) + space_w);
                    heading_text[4].indent = -((hashtag_w * 5) + space_w);
                    heading_text[5].indent = -((hashtag_w * 6) + space_w);
                    heading_text[0].indent_set = true;
                    heading_text[1].indent_set = true;
                    heading_text[2].indent_set = true;
                    heading_text[3].indent_set = true;
                    heading_text[4].indent_set = true;
                    heading_text[5].indent_set = true;
                }
            }
        }
    }
}