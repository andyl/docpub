# What's New Data

We desire to have a feature "what's new", that highlights new content since the last visit.

The way this is envisioned to work:
- the app sets a cookie in the browser {last_visit_date, last_git_commit} 
- if there is new content, show a "what's new" button 
- there is a summary page which shows all the changes
- change bars show elements in the file that have changes

For now it is difficult to envision the right user-interface for this feature.

I know that I'd like to keep it simple.  Git diffs are too complex.  Change
bars on the side of the screen seem just about right, with the ability to jump
to next and prev change blocks.  A summary view showing all the changed
elements seems nice.

So for Phase 1, let's just focus on the required data structures:

- data in the cookie 
- data structure that, given the cookie as input, show what has changed 
- how to generate the data structure from the underlying Git repo

Once we have that defined and working, we'll move on to Phase 2 - What's New UI
