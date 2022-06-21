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
    /**
     * Attempts to strip markdown from given string
     *
     * @param sentence String to strip markdown from
     */
    public string strip_markdown (string sentence) {
        string result = sentence;
        try {
            Regex is_link = new Regex ("\\[([^\\[]+?)\\](\\([^\\)\\n]+?\\))", RegexCompileFlags.CASELESS, 0);
            result = is_link.replace_eval (
                result,
                (ssize_t) result.length,
                0,
                RegexMatchFlags.NOTEMPTY,
                (match_info, result) =>
                {
                    var title = match_info.fetch (1);
                    result.append (title);
                    return false;
                });

            result = result.replace ("*", "");
            result = result.replace ("[", "");
            result = result.replace ("]", "");
            result = result.replace ("_", "");
            while (result.has_prefix ("\n") || result.has_prefix ("#") || result.has_prefix (">") ||
                   result.has_prefix (" ") || result.has_prefix ("-") || result.has_prefix ("+")) {
                result = result.substring (1);
            }
        } catch (Error e) {
            warning ("Could not strip markdown: %s", e.message);
        }

        return result;
    }

    /**
     * TimedMutex hold a lock for a given time before allowing an action
     * to be taken again
     */
    public class TimedMutex {
        private bool can_action;
        private Mutex droptex;
        private int delay;

        /**
         * Constructs a TimedMutex object, defaults to 1.5 seconds
         *
         * @param milliseconds_delay Amount of time to hold lock before releasing
         */
        public TimedMutex (int milliseconds_delay = 1500) {
            if (milliseconds_delay < 100) {
                milliseconds_delay = 100;
            }

            delay = milliseconds_delay;
            can_action = true;
            droptex = Mutex ();
        }

        /**
         * Returns true if enough time has ellapsed since the last call.
         * Returns false if action should not be taken.
         */
        public bool can_do_action () {
            bool res = false;

            if (droptex.trylock()) {
                if (can_action) {
                    res = true;
                    can_action = false;
                }
                Timeout.add (delay, clear_action);
                droptex.unlock ();
            }
            return res;
        }

        private bool clear_action () {
            droptex.lock ();
            can_action = true;
            droptex.unlock ();
            return false;
        }
    }

    /**
     * Grabs a reasonable amount of text around the cursor
     *
     * @param start Begining place of where to look
     * @param end End of place of where to look
     * @param force_lines ???
     */
    public void get_chunk_of_text_around_cursor (ref Gtk.TextIter start, ref Gtk.TextIter end, bool force_lines = false) {
        start.backward_line ();

        //
        // Try to make sure we don't wind up in the middle of
        // CHARACTER
        // [Iter]Dialogue
        //
        int line_checks = 0;
        if (!force_lines) {
            while (start.get_char () != '\n' && start.get_char () != '\r' && line_checks <= 5) {
                if (!start.backward_line ()) {
                    break;
                }
                line_checks += 1;
            }

            end.forward_line ();
            line_checks = 0;
            while (end.get_char () != '\n' && end.get_char () != '\r' && line_checks <= 5) {
                if (!end.forward_line ()) {
                    break;
                }
                line_checks += 1;
            }
        } else {
            while (line_checks <= 5) {
                if (!start.backward_line ()) {
                    break;
                }
                line_checks += 1;
            }

            end.forward_line ();
            line_checks = 0;
            while (line_checks <= 5) {
                if (!end.forward_line ()) {
                    break;
                }
                line_checks += 1;
            }
        }
    }
}