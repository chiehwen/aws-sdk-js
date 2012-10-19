# Copyright 2011-2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

helpers = require('../helpers'); AWS = helpers.AWS
require('../../lib/rest_xml_service')

describe 'AWS.RESTXMLService', ->

  xmlns = 'http://mockservice.com/xmlns'

  operation = null

  MockRESTXMLService = AWS.util.inherit AWS.RESTXMLService,
    constructor: (config) ->
      this.serviceName = 'mockservice'
      AWS.RESTXMLService.call(this, config)

  beforeEach ->

    MockRESTXMLService.prototype.api =
      xmlNamespace: xmlns
      operations:
        sampleOperation:
          m: 'POST' # http method
          u: '/'    # uri
          i: null   # no params
          o: null   # no ouputs

    AWS.Service.defineMethods(MockRESTXMLService)

    operation = MockRESTXMLService.prototype.api.operations.sampleOperation

  svc = new MockRESTXMLService()

  it 'defines a method for each api operation', ->
    expect(typeof svc.sampleOperation).toEqual('function')

  describe 'buildRequest', ->

    buildRequest = (params) ->
      svc.buildRequest('sampleOperation', params)

    describe 'empty bodies', ->

      it 'defaults body to null when there are no inputs', ->
        operation.i = null
        expect(buildRequest().body).toEqual(null)

      it 'defaults body to null when all inputs are uri or header values', ->
        operation.u = '/{Bucket}'
        operation.i = {m:{Bucket:{l:'uri',r:1},ACL:{n:'x-amz-acl',l:'header'}}}
        params = { Bucket:'abc', ACL:'canned-acl' }
        req = buildRequest(params)
        expect(req.body).toEqual(null)
        expect(req.uri).toEqual('/abc')
        expect(req.headers['x-amz-acl']).toEqual('canned-acl')

    describe 'string bodies', ->

      it 'populates the body with string types directly', ->
        operation.u = '/{Bucket}'
        operation.i = {m:{Bucket:{l:'uri',r:1},Data:{t:'s',l:'body'}}}
        params = { Bucket: 'bucket-name', Data: 'abc' }
        expect(buildRequest(params).body).toEqual('abc')

    describe 'xml bodies', ->

      describe 'structures', ->

        it 'wraps simple structures with location of body', ->
          operation.i = {n:'Config',m:{Name:{},State:{}}}
          params = { Name:'abc', State: 'Enabled' }
          xml = """
          <Config xmlns="#{xmlns}">
            <Name>abc</Name>
            <State>Enabled</State>
          </Config>
          """
          matchXML(buildRequest(params).body, xml)

        it 'orders xml members by the order they appear in the rules', ->
          operation.i = {n:'Config',m:{Count:{t:'i'},State:{}}}
          params = { State: 'Disabled', Count: 123 }
          xml = """
          <Config xmlns="#{xmlns}">
            <Count>123</Count>
            <State>Disabled</State>
          </Config>
          """
          matchXML(buildRequest(params).body, xml)

        it 'can serializes structures into XML', ->
          operation.i =
            n: 'Data',
            m:
              Name: {}
              Details:
                t: 'o'
                m:
                  Abc: {}
                  Xyz: {}
          params =
            Details:
              Xyz: 'xyz'
              Abc: 'abc'
            Name: 'john'
          xml = """
          <Data xmlns="#{xmlns}">
            <Name>john</Name>
            <Details>
              <Abc>abc</Abc>
              <Xyz>xyz</Xyz>
            </Details>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'serializes empty structures as empty element', ->
          operation.i = {n:'Data',m:{Config:{t:'o',m:{Foo:{},Bar:{}}}}}
          params = { Config: {} }
          xml = """
          <Data xmlns="#{xmlns}">
            <Config/>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'does not serialize missing members', ->
          operation.i = {n:'Data',m:{Config:{t:'o',m:{Foo:{},Bar:{}}}}}
          params = { Config: { Foo: 'abc' } }
          xml = """
          <Data xmlns="#{xmlns}">
            <Config>
              <Foo>abc</Foo>
            </Config>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

      describe 'lists', ->

        it 'serializes lists (default member names)', ->
          operation.i = {n:'Data',m:{Aliases:{t:'a',m:{}}}}
          params = {Aliases:['abc','mno','xyz']}
          xml = """
          <Data xmlns="#{xmlns}">
            <Aliases>
              <member>abc</member>
              <member>mno</member>
              <member>xyz</member>
            </Aliases>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'serializes lists (custom member names)', ->
          operation.i = {n:'Data',m:{Aliases:{t:'a',m:{n:'Alias'}}}}
          params = {Aliases:['abc','mno','xyz']}
          xml = """
          <Data xmlns="#{xmlns}">
            <Aliases>
              <Alias>abc</Alias>
              <Alias>mno</Alias>
              <Alias>xyz</Alias>
            </Aliases>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'includes lists elements even if they have no members', ->
          operation.i = {n:'Data',m:{Aliases:{t:'a',m:{n:'Alias'}}}}
          params = {Aliases:[]}
          xml = """
          <Data xmlns="#{xmlns}">
            <Aliases/>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'serializes lists of structures', ->
          operation.i =
            n: 'Data'
            m:
              Points:
                t: 'a'
                m:
                  t: 'o'
                  n: 'Point'
                  m:
                    X: {t:'n'}
                    Y: {t:'n'}
          params = {Points:[{X:1.2,Y:2.1},{X:3.4,Y:4.3}]}
          xml = """
          <Data xmlns="#{xmlns}">
            <Points>
              <Point>
                <X>1.2</X>
                <Y>2.1</Y>
              </Point>
              <Point>
                <X>3.4</X>
                <Y>4.3</Y>
              </Point>
            </Points>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

      describe 'numbers', ->

        it 'integers', ->
          operation.i = {n:'Data',m:{Count:{t:'i'}}}
          params = { Count: 123.0 }
          xml = """
          <Data xmlns="#{xmlns}">
            <Count>123</Count>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'floats', ->
          operation.i = {n:'Data',m:{Count:{t:'n'}}}
          params = { Count: 123.123 }
          xml = """
          <Data xmlns="#{xmlns}">
            <Count>123.123</Count>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

      describe 'timestamps', ->

        it 'true', ->
          operation.i = {n:'Data',m:{Enabled:{t:'b'}}}
          params = { Enabled: true }
          xml = """
          <Data xmlns="#{xmlns}">
            <Enabled>true</Enabled>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'false', ->
          operation.i = {n:'Data',m:{Enabled:{t:'b'}}}
          params = { Enabled: false }
          xml = """
          <Data xmlns="#{xmlns}">
            <Enabled>false</Enabled>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

      describe 'timestamps', ->

        time = new Date()

        it 'iso8601', ->
          MockRESTXMLService.prototype.api.timestampFormat = 'iso8601'
          operation.i = {n:'Data',m:{Expires:{t:'t'}}}
          params = { Expires: time }
          xml = """
          <Data xmlns="#{xmlns}">
            <Expires>#{AWS.util.date.iso8601(time)}</Expires>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'rfc822', ->
          MockRESTXMLService.prototype.api.timestampFormat = 'rfc822'
          operation.i = {n:'Data',m:{Expires:{t:'t'}}}
          params = { Expires: time }
          xml = """
          <Data xmlns="#{xmlns}">
            <Expires>#{AWS.util.date.rfc822(time)}</Expires>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)

        it 'unix timestamp', ->
          MockRESTXMLService.prototype.api.timestampFormat = 'unixTimestamp'
          operation.i = {n:'Data',m:{Expires:{t:'t'}}}
          params = { Expires: time }
          xml = """
          <Data xmlns="#{xmlns}">
            <Expires>#{AWS.util.date.unixTimestamp(time)}</Expires>
          </Data>
          """
          matchXML(buildRequest(params).body, xml)
