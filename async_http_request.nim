type Response* = tuple[status: string, body: string]

type Handler* = proc (data: Response)

when not defined(js):
    import asyncdispatch, httpclient, threadpool
    when defined(android):
        # For some reason pthread_t is not defined on android
        {.emit: """/*INCLUDESECTION*/
        #include <pthread.h>"""
        .}

    type ThreadedHandler* = proc(r: Response, ctx: pointer) {.nimcall.}

    proc ayncHTTPRequest(url, httpMethod, extraHeaders, body: string, handler: ThreadedHandler, ctx: pointer) =
        try:
            let resp = request(url, "http" & httpMethod, extraHeaders, body, sslContext = nil)
            handler((resp.status, resp.body), ctx)
        except:
            echo "Exception caught: ", getCurrentExceptionMsg()
            echo getCurrentException().getStackTrace()

    proc sendRequestThreaded*(meth, url, body: string, headers: openarray[(string, string)], handler: ThreadedHandler, ctx: pointer = nil) =
        ## handler might not be called on the invoking thread
        var extraHeaders = ""
        for h in headers:
            extraHeaders &= h[0] & ": " & h[1] & "\r\n"
        spawn ayncHTTPRequest(url, meth, extraHeaders, body, handler, ctx)

when defined(js):
    type
        XMLHTTPRequest* = ref XMLHTTPRequestObj
        XMLHTTPRequestObj {.importc.} = object
            responseType*: cstring

    proc open*(r: XMLHTTPRequest, httpMethod, url: cstring) {.importcpp.}
    proc send*(r: XMLHTTPRequest) {.importcpp.}
    proc send*(r: XMLHTTPRequest, body: cstring) {.importcpp.}
    proc addEventListener*(r: XMLHTTPRequest, event: cstring, listener: proc(e: ref RootObj)) {.importcpp.}
    proc addEventListener*(r: XMLHTTPRequest, event: cstring, listener: proc()) {.importcpp.}

    proc newXMLHTTPRequest*(): XMLHTTPRequest =
        {.emit: """
        if (window.XMLHttpRequest)
            `result` = new XMLHttpRequest();
        else
            `result` = new ActiveXObject("Microsoft.XMLHTTP");
        """.}

    proc sendRequest*(meth, url, body: string, headers: openarray[(string, string)], handler: Handler) =
        let reqListener = proc (r: ref RootObj) =
            var cbody: cstring
            var cstatus: cstring
            {.emit: """
            `cbody` = `r`.target.responseText;
            `cstatus` = `r`.target.statusText;
            """.}
            handler(($cstatus,  $cbody))

        let oReq = newXMLHTTPRequest()
        oReq.responseType = "text"
        oReq.addEventListener("load", reqListener)
        oReq.open(meth, url)
        if body.isNil:
            oReq.send()
        else:
            oReq.send(body)

    template sendRequest*(meth, url, body: string, headers: openarray[(string, string)], handler: proc(body: string)) =
        sendRequest(meth, url, body, headers, proc(r: Response) = handler(r.body))
