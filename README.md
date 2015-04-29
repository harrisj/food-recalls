# Food Recalls

This may shock you, but the government can be terrible at collecting data sometimes. For instance, food recalls. Currently, both the USDA and FDA have split responsibility for food safety and coordinating the release of recall information. There are a variety of questions we might want to ask about this data source (common causes, food categories, volumes of food recalled), but all the data is hidden within press releases and there are no additional databases of quantitative information I have been able to find via FOIA request.

So, I rolled my own. As I [documented in an article for Source](https://source.opennews.org/en-US/learning/how-sausage-gets-made/), it's possible to extract data from the press releases with regular expressions and a bit of tenacity. I am going to make this code open source and see if I can host this database as a service online.

## What We Could Learn From Recalls

There is a variety of information embedded in recall press releases generally:

* Recall title
* Recalling company
* The recall reason
* Food categories (derived from the food mentioned)
* The date the recall was issued
* The geographic range of the recall

In addition, we sometimes can get additional information from some recalls

* Supermarkets that sold the food (important for generic food brands)
* Specific product SKUs and labels
* Recalls that were triggered by other recalls (ie, tainted peanut butter affecting other things)
* The volume of the recall (often but not always in pounds)

## What We Can't Learn From Recalls

It might be tempting to use this database as a window into the state of food safety in America. That's a bad idea. There are many reasons why a food contamination outbreak would not show up in the recalls database (for instance, if it's not a packaged food product). Furthermore, some categories may be misleading: for instance, `undeclared allergen` recalls usually mean something was put in the wrong box, and New York states classifies all uneviscerated fish as botulism cases even if no actual botulism was detected. Be careful before you try to derive some sweeping conclusion from this data. Ultimately, other databases like those collected by the CDC may provide a better picture, but cover also problems with food preparation, and small localized outbreaks. Ultimately, there is no one database or collection of databases that provides a solid dashboard of how safe food is in America and that's part of the problem.

## Thanks

I would like to thank the _New York Times_ for giving me the support to work on the initial version of this, even if there was ultimately no reporting angle within it.