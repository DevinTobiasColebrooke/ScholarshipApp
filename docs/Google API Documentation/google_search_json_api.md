Make a request
REST, or Representational State Transfer, in the Custom Search JSON API is somewhat different from the usual RESTful APIs. Instead of providing access to resources, the API provides access to a service. As a result, the API provides a single URI that acts as the service endpoint.

You can retrieve results for a particular search by sending an HTTP GET request to its URI. You pass in the details of the search request as query parameters. The format for the Custom Search JSON API URI is:


https://www.googleapis.com/customsearch/v1?[parameters]
Three query [parameters] are required with each search request:

API key - Use the key query parameter to identify your application.

Programmable Search Engine ID - Use cx to specify the Programmable Search Engine you want to use to perform this search. The search engine must be created with the Control Panel Note: The Search Engine ID (cx) can be of different format (e.g. 8ac1ab64606d234f1)
Search query - Use the q query parameter to specify your search expression.

All other query parameters are optional.

Here is an example of a request which searches a test Programmable Search Engine for lectures:


GET https://www.googleapis.com/customsearch/v1?key=INSERT_YOUR_API_KEY&cx=017576662512468239146:omuauf_lfve&q=lectures
Note: The limit on the length of the search request should be within 2048 characters.
Query parameters
There are two types of parameters that you can pass in your request:

API-specific parameters - define properties of your search, like the search expression, number of results, language etc.
Standard query parameters - define technical aspects of your request, like the API key.
All parameter values need to be URL encoded.

API-specific query parameters
Request parameters that apply specifically to the Custom Search JSON API and define your search request are summarized in the reference.

Standard query parameters
Query parameters that apply to all Custom Search JSON API operations are documented at System Parameters.

Response data
If the request succeeds, the server responds with a 200 OK HTTP status code and the response data in JSON format. You can look up the response data structure in the reference.

The response data is a JSON object that includes three types of properties:

Metadata describing the requested search (and, possibly, related search requests)
Metadata describing the Programmable Search Engine
Search results
For a detailed description of each property, see the reference.

Search request metadata
The search metadata includes:

url property, which has information about the OpenSearch template used for the results returned in this request.
queries property, which is an array of objects describing the characteristics of possible searches. The name of each object in the array is either the name of an OpenSearch query role or one of the two custom roles defined by this API: previousPage and nextPage. Possible query role objects include:
request: Metadata describing the query for the current set of results.
This role is always present in the response.
It is always an array with just one element.
nextPage: Metadata describing the query to use for the next page of results.
This role is not present if the current results are the last page. Note: This API returns up to the first 100 results only.
When present, it is always a array with just one element.
previousPage: Metadata describing the query to use for the previous page of results.
Not present if the current results are the first page.
When present, it is always a array with just one element.
Search engine metadata
The context property has metadata describing the search engine that performed the search query. It includes the name of the search engine, and any facet objects it provides for refining a search.

Search results
The items array contains the actual search results. The search results include the URL, title and text snippets that describe the result. In addition, they can contain rich snippet information, if applicable.

If the search results include a promotions property, it contains a set of promotions.

REST from JavaScript
You can invoke the Custom Search JSON API using REST from JavaScript, using the callback query parameter and a callback function. This lets you write rich applications that display Programmable Search Engine data without writing any server side code.

The following example uses this approach to display the first page of search results for the query lecture:


<html>
<head>
<title>Custom Search JSON API Example</title>
</head>
<body>
    <div id="content"></div>
    <p id="demo"></p>
    <script>
    function hndlr(response) {
      if (response.items == null) {
        document.getElementById("demo").innerHTML +=`<h3> No Results Found </h3>`;
      } else {
        for (var i = 1; i < response.items.length; i++) {
          var item = response.items[i];
          // Make sure HTML in item.htmlTitle is escaped.
          document.getElementById("content").append(
            document.createElement("br"),
            document.createTextNode(item.htmlTitle)
          );
        }
      }
    }
    </script>
    <script src="https://www.googleapis.com/customsearch/v1?key=YOUR-KEY&cx=017576662512468239146:omuauf_lfve&q=lecture&callback=hndlr">
    </script>
  </body>
</html>

Working with partial resources
Another way to improve the performance of your API calls is by requesting only the portion of the data that you're interested in. This lets your application avoid transferring, parsing, and storing unneeded fields, so it can use resources including network, CPU, and memory more efficiently.

Partial response
By default, the server sends back the full representation of a resource after processing requests. For better performance, you can ask the server to send only the fields you really need and get a partial response instead.

To request a partial response, use the fields request parameter to specify the fields you want returned. You can use this parameter with any request that returns response data.

Example
The following example shows the use of the fields parameter with a generic (fictional) "Demo" API.

Simple request: This HTTP GET request omits the fields parameter and returns the full resource.


https://www.googleapis.com/demo/v1
Full resource response: The full resource data includes the following fields, along with many others that have been omitted for brevity.


{
  "kind": "demo",
  ...
  "items": [
  {
    "title": "First title",
    "comment": "First comment.",
    "characteristics": {
      "length": "short",
      "accuracy": "high",
      "followers": ["Jo", "Will"],
    },
    "status": "active",
    ...
  },
  {
    "title": "Second title",
    "comment": "Second comment.",
    "characteristics": {
      "length": "long",
      "accuracy": "medium"
      "followers": [ ],
    },
    "status": "pending",
    ...
  },
  ...
  ]
}
Request for a partial response: The following request for this same resource uses the fields parameter to significantly reduce the amount of data returned.


https://www.googleapis.com/demo/v1?fields=kind,items(title,characteristics/length)
Partial response: In response to the request above, the server sends back a response that contains only the kind information along with a pared-down items array that includes only HTML title and length characteristic information in each item.


200 OK

{
  "kind": "demo",
  "items": [{
    "title": "First title",
    "characteristics": {
      "length": "short"
    }
  }, {
    "title": "Second title",
    "characteristics": {
      "length": "long"
    }
  },
  ...
  ]
}
Note that the response is a JSON object that includes only the selected fields and their enclosing parent objects.

Details on how to format the fields parameter is covered next, followed by more details about what exactly gets returned in the response.

Fields parameter syntax summary
The format of the fields request parameter value is loosely based on XPath syntax. The supported syntax is summarized below, and additional examples are provided in the following section.

Use a comma-separated list to select multiple fields.
Use a/b to select a field b that is nested within field a; use a/b/c to select a field c nested within b.
Exception: For API responses that use "data" wrappers, where the response is nested within a data object that looks like data: { ... }, do not include "data" in the fields specification. Including the data object with a fields specification like data/a/b causes an error. Instead, just use a fields specification like a/b.

Use a sub-selector to request a set of specific sub-fields of arrays or objects by placing expressions in parentheses "( )".
For example: fields=items(id,author/email) returns only the item ID and author's email for each element in the items array. You can also specify a single sub-field, where fields=items(id) is equivalent to fields=items/id.

Use wildcards in field selections, if needed.
For example: fields=items/pagemap/* selects all objects in a pagemap.

More examples of using the fields parameter
The examples below include descriptions of how the fields parameter value affects the response.

Note: As with all query parameter values, the fields parameter value must be URL encoded. For better readability, the examples in this document omit the encoding.

Identify the fields you want returned, or make field selections.
The fields request parameter value is a comma-separated list of fields, and each field is specified relative to the root of the response. Thus, if you are performing a list operation, the response is a collection, and it generally includes an array of resources. If you are performing an operation that returns a single resource, fields are specified relative to that resource. If the field you select is (or is part of) an array, the server returns the selected portion of all elements in the array.

Here are some collection-level examples:
Examples	Effect
items	Returns all elements in the items array, including all fields in each element, but no other fields.
etag,items	Returns both the etag field and all elements in the items array.
items/title	Returns only the title field for all elements in the items array.

Whenever a nested field is returned, the response includes the enclosing parent objects. The parent fields do not include any other child fields unless they are also selected explicitly.
context/facets/label	Returns only the label field for all members of the facets array, which is itself nested under the context object.
items/pagemap/*/title	For each element in the items array, returns only the title field (if present) of all objects that are children of pagemap.

Here are some resource-level examples:
Examples	Effect
title	Returns the title field of the requested resource.
author/uri	Returns the uri sub-field of the author object in the requested resource.
links/*/href
Returns the href field of all objects that are children of links.
Request only parts of specific fields using sub-selections.
By default, if your request specifies particular fields, the server returns the objects or array elements in their entirety. You can specify a response that includes only certain sub-fields. You do this using "( )" sub-selection syntax, as in the example below.
Example	Effect
items(title,author/uri)	Returns only the values of the title and author's uri for each element in the items array.
Handling partial responses
After a server processes a valid request that includes the fields query parameter, it sends back an HTTP 200 OK status code, along with the requested data. If the fields query parameter has an error or is otherwise invalid, the server returns an HTTP 400 Bad Request status code, along with an error message telling the user what was wrong with their fields selection (for example, "Invalid field selection a/b").

Here is the partial response example shown in the introductory section above. The request uses the fields parameter to specify which fields to return.


https://www.googleapis.com/demo/v1?fields=kind,items(title,characteristics/length)
The partial response looks like this:


200 OK

{
  "kind": "demo",
  "items": [{
    "title": "First title",
    "characteristics": {
      "length": "short"
    }
  }, {
    "title": "Second title",
    "characteristics": {
      "length": "long"
    }
  },
  ...
  ]
}
Note: For APIs that support query parameters for data pagination (maxResults and nextPageToken, for example), use those parameters to reduce the results of each query to a manageable size. Otherwise, the performance gains possible with partial response might not be realized.

The Custom Search JSON API lets you develop websites and applications to retrieve and display search results from Programmable Search Engine programmatically. With this API, you can use RESTful requests to get either web search or image search results in JSON format.

Data format
Custom Search JSON API can return results in JSON data format.

Related documents
The Custom Search JSON API uses the OpenSearch 1.1 Specification.

Prerequisites
Search engine ID
Before using the Custom Search JSON API you will first need to create and configure your Programmable Search Engine. If you have not already created a Programmable Search Engine, you can start by visiting the Programmable Search Engine control panel.

Follow the tutorial to learn more about different configuration options.

After you have created a Programmable Search Engine, visit the help center to learn how to locate your Search engine ID.

API key
Custom Search JSON API requires the use of an API key. Get a Key

Pricing
Custom Search JSON API provides 100 search queries per day for free. If you need more, you may sign up for billing in the API Console. Additional requests cost $5 per 1000 queries, up to 10k queries per day.

Monitoring
Basic monitoring for the Custom Search JSON API is available through Cloud Platform Console's API Dashboard. For more advanced monitoring Google Cloud's Operations suite (formerly Stackdriver) is available.

With Google Cloud Operations you can create custom dashboards, set up alerts, and access metrics data programmatically. To access Custom Search JSON API usage data in Google Cloud Operations, select "Resource type: Consumed API" and filter on "service = 'customsearch.googleapis.com'" in the Query Builder.

See Monitoring Your API Usage for a discussion of the different monitoring and alerting capabilities provided by the API Dashboard and the Google Cloud Operations suite.