# discourse-onebox-assistant

In order to render a onebox, your Discourse server must crawl the site at the remote link to pick up the right metadata from the page source.  Often your server is blocked from pulling back the required page to generate the preview, either because of a blanket ban on your IP/User Agent or a rate limit.  This plugin gets around those situations.  This plugin helps guarantee onebox previews are rendered reliably by performing the required crawl of the remote site using a proxy crawl service instead of doing so directly.  

[See further here](https://meta.discourse.org/t/onebox-assistant-a-plugin-to-help-onebox-do-its-job/107405).
