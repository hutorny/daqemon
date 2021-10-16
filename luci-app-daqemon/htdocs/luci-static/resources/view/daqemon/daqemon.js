/* daqemon.js - UI controller
   This file is a part of DAQEMON application
   Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
   DAQEMON is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License v2
   as published by the Free Software Foundation;
   License:  https://opensource.org/licenses/GPL-2.0              */

/**
 * Sugar for query selectors
 */
function $all(sel) {
	return (typeof sel === 'string') ? document.querySelectorAll(sel) : sel;
}

function $arr(sel) {
	if( sel === null ) return [];
	return (typeof sel === 'string')
		? Array.apply(null, $all(sel))
		: Array.apply(null, sel);
}

function $one(sel) {
	return (typeof sel === 'string') ? document.querySelector(sel) : sel;
}

function $for(sel, fn, ths) {
	if(sel) $arr(sel).forEach(fn, ths);
}

$for.escape = function(s) {
	return s.replace($for.escape.regexp, "\\$1");
};

$for.escape.regexp = /([!"#$%&'()*+,.\/:;<=>?@\[\\\]^`{|}~])/g;

$one.escape = $for.escape;



function $resname(url) {
	if( ! url ) return url;
	var p = url.split('/');
	if( p[1] === '' ) {
		p.shift();	// http
	}
	if( p[0] === '' ) {
		p.shift();	// ''
		p.shift();	// host
	}
	return p.join('/');
}

/* originated from
 * http://stackoverflow.com/questions/201183/how-to-determine-equality-for-two-javascript-objects
 */
function equals(x, y) {
	return (x && y && typeof x === 'object' && typeof y === 'object') ?
		(Object.keys(x).length === Object.keys(y).length) &&
			Object.keys(x).every(function(key) {
				return equals(x[key], y[key]);
			}, true) : (x === y);
}

/**
 *  Utility functions
 */
function isTrueNaN(val) { return typeof val === 'number' && isNaN(val); }

function augument(err, message, status, data, type) {
	err.message = message;
	err.status = status;
	err.data = data;
	err.type = type;
	return err;
}

function format(fmt, ...args) {
	return function () {
		var s = this;
		for(let i in arguments) s = s.replace('{'+i+'}',arguments[i]);
		return s
	}.apply(fmt, [...args]);
}


/** Communication protocol classes																					*/
/** Rest: implements http requests: GET/POST/DELETE
 */
class Rest {
	constructor(baseurl, auth) {
		this._auth = this._makeauth(auth);
		this._url  = baseurl;
	}
	/* All methods a protected */
	_makeauth(url, text) {
		switch (typeof(this._auth)) {
		case 'function' : return this._auth(url, text);
		case 'string'   :
		case 'object'   : return this._auth ? this._auth : url;
		default			: return url;
		}
	}
	_makecomposer(composer) {
		switch(typeof composer) {
		case 'function' : return composer;
		case 'object':
		case 'undefined': return (base, prop, method)=>base + prop;
		default   		: return (base, prop, method)=>base + prop + composer;
		}
	}
	_send(method, url, obj, headers) {
		var text = (typeof(obj) === 'object') ? JSON.stringify(obj) : (obj !== undefined) && obj.toString();
		var auth = this._makeauth(url, text);
		var url  = typeof(auth) === 'string' ? auth : url;
		var xhr = new XMLHttpRequest();
		//xhr.withCredentials = true; // this requires CORS header without '*'
		var type = (typeof(obj) === 'object') ? 'application/json' : 'plain/text';
		var err = new Error();
		return new Promise(function (resolve, reject) {
			xhr.onreadystatechange = function () {
				if( this.readyState == 4 ) {
					if( this.status >= 200  && this.status <= 204 ) {
						var ctype = this.getResponseHeader('Content-Type');
						if( ctype === 'application/json' ) {
							try {
								var data = JSON.parse(this.responseText);
								resolve(data);
							} catch(e) {
								reject(augument(err, e.message, this.statusText, this.responseText, ctype));
							}
						}
						else {
							resolve(this.responseText);
						}
					} else {
						if ( this.status )
							reject(augument(err, this.statusText, this.statusText, this.responseText));
						else {
							reject(augument(err, 'HTTP Request error (CORS?)'));
						}
					}
				}
			}
			xhr.ontimeout = function () { reject(augument(err,'Network timeout')); };
			xhr.open(method, url);
			xhr.timeout = 2000;

			if( method === 'POST') {
				if( headers )
					for(const [key, value] of Object.entries(headers))
						xhr.setRequestHeader(key, value);
				else
					xhr.setRequestHeader('Content-Type', type);
			} else {
				xhr.setRequestHeader('Accept', 'application/json, plain/text');
			}

			if( typeof(auth) === 'object' ) for(var h in auth) xhr.setRequestHeader(h, auth[h]);
			xhr.send(text);
		});
	}
}

/**
 * Rpc class implements remote procedure call via a local proxy
 */
class Rpc {
	constructor(url, auth, options) {
		this._url = url;
		this._auth = auth;
		this._count = 0;
		this._options = options || {expand_single_object:false}
		var proxy = new Proxy(this,{
			get(self,method){
				return new Proxy(function(){}, {
					apply(){
						var args = [].slice.call(arguments)[2];
						if( args.length == 1 && self.expand_single_object && typeof args[0] === typeof {})
							// if only one argument and it is of object type and expand_single_object is true
							args = args[0]; // assume it is parameter by names
						return self._call(method,args);
					}
				});
			}
		});
		return proxy;
	}
	/* All methods a private */
	_makeauth(text) {
		switch (typeof(this._auth)) {
		case 'function' : return this._auth(this._url, text);
		case 'string'   :
		case 'object'   : return this._auth ? this._auth : this._url
		}
		return this._url;
	}
	_put(obj) {
		var text = JSON.stringify(obj);
		var auth = this._makeauth(text);
		var url  = typeof(auth) == 'string' ? auth : this._url;
		if (typeof(auth) === 'string') url
		var xhr = new XMLHttpRequest();
		var err = new Error();
		return new Promise(function (resolve, reject) {
			xhr.onreadystatechange = function () {
				if( this.readyState == 4 ) {
					if( this.status >= 200  && this.status <= 204 ) {
						var ctype = this.getResponseHeader('Content-Type');
						if( ctype === 'application/json' || ctype === 'application/json-rpc' ) {
							try {
								var data = JSON.parse(this.responseText);
								if (data.jsonrpc != '2.0' ) reject(new Error('Not valid JSON-RPC responce'));
								else {
									if( data.error ) reject(new Error(data.error.message))
									else resolve(data.result);
								}
							} catch(e) {
								reject(augument(err, e.message, this.statusText, this.responseText, ctype));
							}
						}
						else {
							reject(augument(err, 'Invalid content type', this.statusText, this.responseText, ctype));
						}
					} else {
						if ( this.status )
							reject(augument(err, this.statusText, this.statusText, this.responseText));
						else
							reject(augument(err, 'HTTP Request error (CORS?)'));
					}
				}
			}
			xhr.ontimeout = function () { reject(augument(err, 'Network timeout')); };
			xhr.open('POST', url);
			xhr.timeout = 10000;
			xhr.setRequestHeader('Content-Type', 'application/json-rpc');
			if( typeof(auth) === 'object' ) for(var h in auth) xhr.setRequestHeader(h, auth[h]);
			xhr.send(text);
		});
	}
	_call(method, params) {
		var id  = ++this._count;
		var res = this._put({jsonrpc:"2.0", method:method, params: params, id: id});
		res.id = id;
		return res;
	}
}

/**
 * EmonAPI - implements REST methods for accessing EmonCMS
 */
class EmonAPI extends Rest {
	constructor(server, url, composer) {
		super(url || server.url, EmonAPI.auth(server.apikey));
		this._composer = this._makecomposer(composer || EmonAPI.composer);
		this._submiturl = server.url + server.uri.submit;
		this.process = {
			set : (inputid, processes)=>this._send('POST', server.url + server.uri.setproc + inputid, 'processlist=' + processes,
					{"Content-Type" : "application/x-www-form-urlencoded; charset=UTF-8"})
		};
	}
	version(){
		return this._send('GET', this._url + 'version');
	}
	list(){
		return this._send('GET', this._url + 'list.json');
	}
	listshort(){
		return this._send('GET', this._composer(this._url, 'listshort', 'get'));
	}
	get(id){
		return this._send('GET', this._composer(this._url, id, 'get'));
	}
	set(id, value){
		return this._send('GET', this._composer(this._url, id, 'set', value));
	}
	create(instance){
		return this._send('GET', this._composer(this._url, '', 'create', instance), instance);
	}
	submit(nodeid, inputs) {
		return this._send('GET', format(this._submiturl, nodeid, JSON.stringify(inputs)));
	}
	async createAll(instances, cb) {
		cb = typeof cb === 'function' ? cb : ()=>{};
		for(const i of instances) {
			var res = await this.create(i);
			if(typeof res != typeof {}) res = { success: false, message: res.toString() }
			i.id = res.success ? res.id : i.id;
			cb(i, res);
		}
		cb(null,null);
	}
}

EmonAPI.serialize = function(obj) {
	var res = '', dlm = '';
	for(var k in obj) { res += dlm + k + '=' + encodeURIComponent(obj[k]); dlm='&'; }
	return res;
}

EmonAPI.auth = function(apikey) { return {Authorization:'Bearer ' + apikey}; }

EmonAPI.composer = function(base, prop, method, args) {
	switch(method) {
	case 'get':
		if(prop ^ 0) return base + 'get.json?id=' + prop;
		break;
	case 'create':
		return base + 'create.json?' + EmonAPI.serialize(args);
	case 'set':
		if(prop ^ 0) return base + 'set.json?id=' + prop + '&fields=' + JSON.stringify(args);
		break;
	case 'delete':
		if(prop ^ 0) return base + 'delete.json?id=' + prop;
		break;
	}
	return base + prop + '.json';
}

EmonAPI.profile_composer= function(base, prop, method, args) {
	if(method !== 'get') throw new Error("Metod " + method + " is not supported");
	if( prop === 'list' || prop === 'listshort' ) return base + prop + '.json';
	return base + 'get.json?type=' + prop;
}
EmonAPI.inputs_composer= function(base, prop, method, args) {
	switch(method) {
	case 'get':
		if(prop ^ 0) return base + 'get.json?id=' + prop;
		break;
	case 'create':
		return base + 'set.json?fields=' + EmonAPI.serialize(args);
	case 'set':
		if(prop ^ 0) return base + 'set.json?inputid=' + prop + '&fields=' + EmonAPI.serialize(args);
		break;
	case 'delete':
		if(prop ^ 0) return base + 'delete?inputid=' + prop;
		break;
	}
	return base + 'get/' + prop;
}

class LuciAPI extends Rest {
	constructor(baseurl) {
		super(baseurl, null);
	}
	log() { return this._send('GET', this._url + '/log'); }
}
/* Controls classes																									*/
/** Multi-Select Dropdown List																						*/
class Msdl {
	constructor(containerselector, groupcontrolselector) {
		if( containerselector ) this.attach(containerselector, groupcontrolselector);
	}
	attach(containerselector, groupcontrolselector) {
		$for(`${containerselector} .msdl-dropdown .preview, ${containerselector} .msdl-dropdown .open`,a=>a.onclick=this.toggle);
		$for(`${containerselector} .msdl-dropdown .selection`,a=>a.onblur=this.hide);
		$for(`${containerselector} .msdl-dropdown .dropdown-control`,a=>a.onchange=this.focus);
		if( groupcontrolselector )
			$for(`${containerselector} ${groupcontrolselector}`,a=>a.onchange=this.switchgroup);
		var css = window.document.styleSheets[0];
		$for(`${containerselector} .msdl-selection-control`,(li)=>this.addrule(css, li.id));
	}
	addrule(sheet, id) {
		sheet.insertRule(`.msdl-dropdown input#${id}[type=checkbox].msdl-selection-control:checked ~ ul.selection label[for=${id}] .checkmark:before {content: '\\2611'}`, sheet.cssRules.length);
		sheet.insertRule(`.msdl-dropdown input#${id}[type=checkbox].msdl-selection-control:checked ~ ul.preview #${id} {display: inline-block}`, sheet.cssRules.length)
	}
	toggle() {
		$for('#'+ this.dataset.control,a=> {
			if( a.dataset.closing === 'true' ) a.checked = false;
			else a.checked = ! a.checked;
			if( a.checked ) Msdl.prototype.focus.apply(this);
		});
	}
	hide() {
		$for('#'+this.dataset.control, a=>{
			a.dataset.closing=true;
			a.checked=false;
			setTimeout(()=>{a.checked=false; a.dataset.closing=false; },300);
		});
	}
	limitHeight() {
		var bounds = this.getBoundingClientRect();
		this.style.maxHeight = Math.max(130,Math.floor(window.top.innerHeight - bounds.top - 60 + window.top.pageYOffset)) + 'px';
	}
	focus() {
		$for('#'+ this.dataset.control + ' ~ .selection', a=> { Msdl.prototype.limitHeight.apply(a); a.focus();});
	}
	switchgroup() {
		$for('input.msdl-group-selector[data-control='+this.dataset.control+']', a=>a.setAttribute('value',this.value));
		$for('input.msdl-selection-control[data-control='+this.dataset.control+']', a=>a.checked=false);
	}
}

/* UI Classes 																										*/
/** UICommon - base class for UI 																					*/
class UICommon {
	constructor() {
		this.model = null;
		this.directives = {};
		this.targets = {};
		this.handlers = {};
		this.controls = {};
		this.timeout = 1000;
		this.daq = new Rpc('/cgi-bin/luci/admin/daqemon/rpc');
	}
	showMessage(err) {
		this.addError(err, 'warning');
	};

	showError(err) {
		this.addError(err, 'error');
	};
	addError(err, clas) {
		if( ! err ) return;
		if( ! this.errors ) return console.log(err);
		if( typeof err === typeof {} ) {
			var log = [err.message, err.status, err.data].join(' ');
			console.error(log);
			err = [err.message || err.toString(), err.status == err.message ? '' : err.status].join(' ');
		}
		this.errors.style.visibility = 'visible';
		var div = document.createElement('div');
		div.className = clas;
		div.innerText = err.trim();
		this.errors.prepend(div);
	}
	init() {
		this.errors = $one('#errors');
	}
	rebase() {
	 	$for($all('a[href^="/"]'), function(a) {
	 		a.href = ORIGIN + '/' + $resname(a.href);
	 	});
	 	$for($all('img[src^="/"]'), function(img) {
	 		img.src = ORIGIN + '/' + $resname(img.src);
	 	});
	}
	convertTo(type, value, id) {
		switch(type) {
		case typeof(0): return Number(value);
		case typeof(false): return Boolean(value);
		case typeof({}): return this.convertToObject(value, id);
		}
		return value;
	}

	convertToObject(value, id) {
		try { return JSON.parse(value); } catch(e) {}
		return value;
	}
	collect(directives, rootdoc, base) {
		var doc = rootdoc;
		var obj = base || {};
		if( typeof doc === 'undefined' ) doc = document;
		if( typeof doc === 'string' ) doc = document.querySelector(doc);
		if( ! doc instanceof HTMLElement ) {
			console.log('Invalid parameter:', rootdoc);
			return null;
		}
		var keys = directives;
		var isarray = Array.isArray(directives);
		if( ! isarray ) keys = Object.keys(directives);
		for(var i in keys) {
			var k = keys[i];
			var d = isarray ? i : k;
			if( k[0] == '{' ) {
				obj[k.slice(1)] = this.collect(directives[d], doc);
			} else {
				if( k[0] == '[' ) {
					if( Array.isArray(directives[d]) ) // Simple array by value
						obj[k.slice(1)] = this.collect(directives[d], doc, []);
					else { // Array by iterator
						const sel = Object.keys(directives[d])[0];
						const dirs = directives[d][sel];
						if( typeof dirs === 'string' ) { // Array of plain values
							obj[k.slice(1)] = Array.apply(null, doc.querySelectorAll(sel)).map(d=>this.collect([dirs], d,[])[0]);
						} else // Array of objects
							obj[k.slice(1)] = Array.apply(null, doc.querySelectorAll(sel)).map(d=>this.collect(dirs, d));
					}
				} else {
					var p = k.split('@');
					var e
					try { e = p[0] ? doc.querySelector(p[0]) : doc; } catch(e) { console.log(e); }
					if( e ) {
						var prop = p[1] || ((e.type && e.type === 'checkbox') ? 'checked' : 'value');
						var props = e;
						if( prop.indexOf('data-') == 0 ) { props = e.dataset; prop = prop.substr(5); }
						else if( prop.indexOf('dataset.') == 0 ) { props = e.dataset; prop = prop.substr(8); }
						var val = e.className.includes('type-int')
							? parseInt(props[prop])
							: e.className.includes('type-float')
							? parseFloat(props[prop])
							: props[prop];
						if( ! isTrueNaN(val) )
							obj[isarray ? d : directives[d]] = val;
					}
				}
			}
		}
		return obj;
	}
	fixAbout() {
		if( ORIGIN && this.controls.about ) {
			var about = $one(this.controls.about);
			var origin = ORIGIN.split('/')[2];
			if( about ) {
				about.setAttribute('href',about.getAttribute('href') + '#' + origin);
			}
		}
	}
	makeURLs(url, uris) {
		var urls = {}
		for(var k in uris) urls[k] = url + uris[k];
		return urls;
	}
	isValidURL(url) { try { return new URL(url); } catch(e) { return false; } }
	setupProgbarCSS() {
		var sheet = window.document.styleSheets[0];
		for(let i = 0; i < 100; i++) {
			sheet.insertRule('.progressbar[data-value="'+i+'"] { background: linear-gradient(to right, #f0f8ff,#f0f8ff '+i+'%,#fff '+i+'%) no-repeat }'
					, sheet.cssRules.length);
		}
	}
	renderValues(data, directives) {
		for(var d in directives) {
			if (!d) continue;
			var id = d.split('@');
			if( id[1] && id[1] !== 'value' ) continue;
			var input = $one(id[0]);
			if( input ) input.setAttribute('value',traverse(data, directives[d].split('.')) || '');
		}
	}
	indicateChanges(text) {
		const root = window.parent.document;
		if( ! root ) return;
		var indicator = root.querySelector('#indicators [data-indicator="daqemon-changes"]') ||
			root.querySelector('.pull-right [data-indicator="daqemon-changes"]')
		if( indicator ) {
			const node = Array.prototype.find.call(indicator.childNodes,n=>n.nodeType === Node.TEXT_NODE);
			node.textContent = text === null ? '' : text;
			indicator.style.display = text === null ? 'none' : 'block';
			return;
		}
		if( text === null ) return;
		const indicators = window.parent.document.querySelector('#indicators') ||
			window.parent.document.querySelector('.pull-right');
		if( ! indicators ) return;
		indicator = root.createElement('span');
		indicator.dataset.indicator = 'daqemon-changes';
		indicator.dataset.style = 'active';
		indicator.appendChild(root.createTextNode(text));
		indicators.appendChild(indicator);
	}
	onUnload(event) {
		if( this.unsaved ) return "Unsaved changes";
	}
	hookup() {
		const ui = this;
		$one('#save').onclick = e=>{
			if( e.target.id == 'save-dropdown' ) return true;
			if( e.target.id == 'next' ) {
				this.next();
			} else if( e.target.id == 'validate' ) {
				this.config.valid = this.validate(true, this.config.client.deviceid, hassome(this.config.inputs));
				this.setSaveAction();
			} else
				this.save(e.target.id == 'saveapply' || e.target.id == 'save' && e.target.action == 'saveapply');
			$one('#save #save-dropdown').checked = false;
		}
		$one('#save .open').onclick = e=> { e.stopPropagation(); }
		$one('#erase').onclick = function() { ui.erase(this.dataset.action=='erase'); }
		this.setEraseAction(this.model && !(this.model.persist && this.model.staging));
		this.setSaveAction();
	}
	setEraseAction(erase) {
		$one('#erase').dataset.action = erase ? 'erase' : 'reset';
	}
	setSaveAction(save) {
		$one('#save').dataset.action = !save && this.config && this.config.valid && ! $one('#node input:invalid') ? 'saveapply' : 'save';
	}
	erase(erase) {
		const message = erase
			? "This will erase current configuration!\nIt is an irreversible action.\nAre you sure to continue?"
			: "This will reset unaplied changes in the current configuration\nAre you sure to continue?";
		if( window.confirm(message) ) {
			this.unsaved = false;
			this.daq.erase().then(d=>this.erased(d, erase)).catch(this.handlers.fail)
		}
	}
	erased(data, erased) {
		this.showMessage(erased ? "Configuration erased, reloading" : "Configuration reset, reloading");
		window.parent.location.reload(true);
	}
	validate(verbose, deviceid, hasinputs) {
		const invalid = $arr('input:invalid, select:invalid');
		if( verbose ) {
			if( ! deviceid ) this.showError("Node is not created on the server");
			if( ! hasinputs ) this.showError("No input is configured");
			if( invalid.length ) {
				invalid.forEach(e=>{e.classList.add('invalid'); this.showError((e.title ? e.title + ' :': '') + e.validationMessage)});
				this.showError("Missing or invalid values:");
			}
		}
		return invalid.length == 0 && !!deviceid && !!hasinputs;
	}
	forward(uri) {
		const parts = window.parent.location.pathname.split('/');
		parts[parts.length-1] = uri;
		window.parent.location.replace(parts.join("/"));
	}
}

/** UISetup - implements Daqemon Setup page																			*/
class UISetup extends UICommon {
	constructor() {
		super();
		var ui = this;
		this.handlers = {
			fail  : err=> this.showError(err),
			onstatechange: function(e) { ui.changed(this,e) },
		}
		this.setupProgbarCSS();
	}

	render(obj) { try {
		if( typeof obj != typeof {} || obj.length == 0 || ! obj.config ) return;
		this.model  = obj;
		this.config = obj.config;
		this.rebase();
		//this.fixAbout();
		const ports = obj.modbus.interfaces.concat("-- Refresh --");
		var slaveids = obj.config.interface.slaveids || obj.modbus.slaveids;
		obj.modbus.slaveids_ = slaveids && slaveids.join(' ');
		if( obj.config.server.url )
			obj.config.server.urls = this.makeURLs(obj.config.server.url, obj.config.server.uri);
		this.daq.status().then(this.renderStatus).catch(this.handlers.fail);
		$p('#interface').render(ports, this.directives.interfaces);
		$p('#baudrate').render(obj.modbus.baudrates,  this.directives.baudrates);
		$p('#parity').render(obj.modbus.parities, this.directives.parities);
		$p('#multirate ').render(obj.daqemon.rates, this.directives.multirates);
		if( ! hassome(this.config.inputs) ) $one('#slaveids').required = true;
		this.renderValues(obj, this.directives.fields);
		$one('#multirate').disabled = !this.config.client.meta.processes.multirate;
		this.setServerURL();
		this.setApplyState();
		this.indicateChanges(this.model.staging ? "Unapplied changes" : null);
		this.hookup(); //$p kills all event handlers in #fieldsets
	} catch(e) { console.log(e); }}

	onURLchange(url) {
		var URL = this.isValidURL(url);
		if( URL && this.config.server.url != url ) {
			this.changeURL(URL, url);
			this.showServerActions(true);
		}
		if (! URL ){
			$one('#server_url').setCustomValidity("Invalid URL");
			$one('#server-actions #register').disabled = true;
			$one('#server-actions #api_help').disabled = true;
		} else {
			$one('#server_url').setCustomValidity('');
		}
	}
	async onPortChange(event, value) {
		if( value[0] !== '-' ) return true;
		event.stopImmediatePropagation();
		event.preventDefault();
		const res = await this.daq.listports();
		if( res.success ) {
			this.model.modbus.interfaces = res.ports;
			if( res.ports.length == 0 ) res.ports = res.ports.concat('');
			const ports = res.ports.concat("-- Refresh --");
			$for('#interface option', (e,i)=> i&&e.parentNode.removeChild(e));
			$p('#interface').render(ports, this.directives.interfaces);
		} else {
			this.showError(res)
		}
		const ui = this;
		$one('#interface').addEventListener('change', function(event) { ui.onPortChange(event, this.value) });
		$one('#interface').addEventListener('change', this.handlers.onstatechange);
		return false;
	}
	changeURL(URL, url) {
		if(! URL.search && ! url.endsWith('/') ) {
			url += '/';
			$one('#server_url').value = url;
		}
		this.config.server.url = url;
		this.config.server.urls = this.makeURLs(this.config.server.url, this.config.server.uri);
		$one('#profile').options.length = 1;
		new EmonAPI(this.config.server, url).version().then((v)=>{
			this.showVersion(v);
			if( this.config.server.apikey ) this.setServerURL();
		}).catch((e)=>this.showError(e));
	}
	changeKey(key) {
		if( this.config.server.apikey == key ) return;
		this.config.server.apikey = key;
		this.setServerURL();
	}
	setServerURL() {
		if( ! this.config.server.apikey ) this.showServerActions(true);
		if( ! this.config.server.url || ! this.config.server.apikey ) return;
		this.config.server.urls = this.makeURLs(this.config.server.url, this.config.server.uri);
		this.node     = new EmonAPI(this.config.server, this.config.server.urls.node);
		this.profiles = new EmonAPI(this.config.server, this.config.server.urls.profiles, EmonAPI.profile_composer);
		new EmonAPI(this.config.server, this.config.server.url).version().then(v=>this.showVersion(v));
		this.getemondata();
	}
	setSaveAction(save) {
		if( hassome(this.config.inputs) )
			super.setSaveAction(save);
		else
			$one('#save').dataset.action = !save && ! $one('#node input:invalid') && this.config.client.deviceid ? 'next' : 'save'
	}
	showServerActions(show) {
		$one('#server-version').style.display = show ? 'none' : null;
		$one('#server-actions').style.display = show ? null : 'none';
		$one('#server-actions #register').disabled = show ? null : 'none';
		$one('#server-actions #api_help').disabled = show ? null : 'none';
		this.setApplyState(! show);
	}
	showVersion(ver) {
		if( $one('#server-actions').style.display !== 'none' ) return;
		$one('#server-version').style.display = null;
		$one('#server_version').value = ver;
	}
	failed(err) {
		success(spin($one('#save'), false),false);
		this.showError(err);
	}
	save(persist, saved) {
		var cfg = this.collect(this.directives.collect);
		if (this.config.client.meta) {
			cfg.client.meta = {
				processes : this.config.client.meta.processes,
				engine: this.config.client.meta.engine,
			};

		}
		if( typeof cfg.interface.slaveids == typeof '') {
			var slaveids = parseIds(cfg.interface.slaveids);
			cfg.interface.slaveids = slaveids;
			$one('#slaveids').value = slaveids.join(' ');
			this.config.interface.slaveids = slaveids;
		}
		cfg.valid = this.validate(false, cfg.client.deviceid, hassome(this.config.inputs));
		spin($one('#save'), true);
		this.daq.saveconfig(cfg, persist).then(r=>saved ? saved(r, persist) : this.saved(r, persist)).catch(e=>this.failed(e));
	}
	next() {
		this.save(false, r=>this.forward('configure'));
	}
	changed(control, event) {
		this.indicateChanges("Unsaved changes");
		this.unsaved  = true;
		this.validate(false, this.config.client.deviceid, hassome(this.config.inputs));
		this.setSaveAction();
		this.setApplyState();
	}
	saved(result, persist) {
		success(spin($one('#save'), false),result && result.success);
		if (! result ) return;
		this.unsaved = false;
		this.indicateChanges(persist ? null : "Unapplied chnages");
		this.setEraseAction(persist);
		this.setSaveAction();
		if( result.success ) {
			if( this.config.server.url !== result.config.server.url ||
				this.config.server.apikey != result.config.server.apikey) {
				this.config.server.url = result.config.server.url;
				this.config.server.urls = this.makeURLs(this.config.server.url, this.config.server.uri);
				this.config = result.config;
				this.setServerURL();
				this.showServerActions(false);
			}
			this.config = result.config;
			if( result.message ) this.showMessage(result.message)
		} else {
			if( result.message ) this.showError(result.message)
		}
	}
	apply() {
		var cfg = this.collect(this.directives.collect);
		spin($one('#apply'), true);
		if( this.config.client.deviceid )
			this.node.set(this.config.client.deviceid, cfg.client).then(r=>this.applied(r)).catch(this.handlers.fail);
		else
			this.node.create(cfg.client).then(r=>this.applied(r)).catch(this.handlers.fail);
	}
	applied(data) {
		spin($one('#apply'), false);
		if( typeof data == typeof {}) {
			success($one('#apply'), data.success == true);
			if( ! data.success && data.message )
				this.showError(data.message);
			if( ! data.success ) {
				if ( this.config.client.deviceid ) {
					this.config.client.deviceid = null;
					$one('#deviceid').setAttribute('value','');
				} else {
					this.node.list().then(r=>this.matchNode(r));
				}
			}
		} else
			if( data ^ 0 ) {
				success($one('#apply'), true);
				$one('#deviceid').setAttribute('value',data);
				this.config.client.deviceid = data ^ 0;
				if( this.model.config.client.type )
					this.profiles.get(this.model.config.client.type).then(d=>{this.saveMeta(d); this.save(false)});
				else
					this.save(false);
			}
	}
	matchNode(nodes) {
		const nodeid = $one('#node_id').value;
		const node = nodes.find(n=>n.nodeid==nodeid);
		if( !node ) return;
		this.config.client.deviceid = node.id;
		$one('#deviceid').setAttribute('value',this.config.client.deviceid);
	}
	init() {
		super.init();
	}
	hookup() {
		var ui = this;
		super.hookup();
		$one('#actions #apply').onclick = ()=> this.apply();
		$one('#service-enable').onclick = function(){
			spin(this,true); // this == button
			ui.daq.enable(this.dataset.status=='off')
				.then(status=>ui.renderStatus(status,this))
				.catch(ui.handlers.fail);
		};
		$one('#service-start').onclick = function(){
			spin(this,true); // this == button
			ui.daq.start(this.dataset.status=='off')
				.then(status=>ui.renderStatus(status, this, true))
				.catch(ui.handlers.fail)
		};
		$one('#service-restart').onclick = function(){
			spin(this,true); // this == button
			ui.daq.restart().then(status=>ui.renderStatus(status, this, true))
			.catch(ui.handlers.fail)
		};
		$one('#find').onclick = ()=> this.scan(1);
		$one('#scan').onclick = ()=> this.scan();
		$one('#server-actions #register').onclick = ()=> this.register();
		$one('#server-actions #api_help').onclick = ()=> this.api_help();
		$one('#server_url').addEventListener('change', function() { ui.onURLchange(this.value) });
		$one('#interface').addEventListener('change', function(event) { ui.onPortChange(event, this.value) });
		$for('.state',a=>a.addEventListener('change',this.handlers.onstatechange));
	}
	scan(count) {
		var ifc = this.collect(this.directives.collect['{interface'])
		ifc = ifc.new_rtu.join(',')
		this.daq.scan(ifc, count).then((scan)=>this.scanned(scan)).catch(this.handlers.fail);
		this.disableScan(true);
		spin($one(count ? '#find' : '#scan'), true);
	}
	disableScan(disable) {
		$one('#find').disabled = disable;
		$one('#scan').disabled = disable;
		$one('#slaveids').readOnly = disable;
		if( ! disable ) {
			spin($one('#scan'), false);
			spin($one('#find'), false);
		}
		return disable;
	}
	poll() {
		this.daq.scan().then((scan)=>this.scanned(scan)).catch(this.handlers.fail);
	}
	scanned(obj) {
		if( !obj ) return this.disableScan(false) || this.showError('Empty responce');
		if( ! obj.success ) return this.disableScan(false) || this.showError(obj.message);
		if( obj.ids ) $one('#slaveids').value = obj.ids.join(' ');
		$one('#slaveids').dataset.value = (obj.done === false && obj.stat <= 100) ? obj.stat : null;
		if( this.disableScan(!obj.done) ) setTimeout(()=>this.poll(), 1000);
	}
	setApplyState() {
		var enabled = this.config.server.url !='' && this.config.server.api_key !='';
		$one('#apply').disabled = ! enabled || !! $one('#node input:invalid');
	}
	async getemondata() {
		try {
			const d = await this.profiles.listshort();
			$one('#server_url').setCustomValidity('');
			$one('#api_key').setCustomValidity('');
			this.setApplyState();
			this.renderProfiles(d);
			if( this.model.config.client.deviceid )
				this.node.get(this.model.config.client.deviceid).then((d)=>this.renderProfile(d)).catch(this.handlers.fail);
		} catch(e) {
			$one('#server_url').setCustomValidity(e.message || e.toString());
			$one('#api_key').setCustomValidity(e.message || e.toString());
			this.showServerActions(true);
			this.handlers.fail(e);
		};
		try {
			const result = await new EmonAPI(this.config.server, this.config.server.urls.dashboard).list();
			this.daq.dashboards(Array.isArray(result));
		} catch(e) {
			this.daq.dashboards(false);
		}
	}
	isCurrentProfile(value) {
		return this.config.client.type===value || (!this.config.client.type && value==='daqemon')
	}
	renderProfiles(list) {
		if( ! list || list.success===false ) {
			this.showError(list.message);
			this.showServerActions(true);
		} else try {
			if( ! UI.model.config.client.type ) UI.model.config.client.type = list.daqemon ?
				'daqemon' : (list.openevse ? 'openevse' : null);
			const profiles = [{id:'',name:''}];
			for(var p in list) if(p) profiles.push({id:p, name:list[p].name});
			$p('#profile').render(profiles, this.directives.profiles);
			$one('#profile').onchange = function() { UI.profileChanged(this.value); }
			if( ! UI.model.config.client.deviceid && $one('#profile').value) $one('#profile').onchange();
		} catch(e) { console.log(e); }
	}
	profileChanged(profile) {
		this.model.config.client.type = profile;
		if( this.model.config.client.type )
			this.profiles.get(this.model.config.client.type).then((d)=>this.saveMeta(d))
	}
	renderProfile(profile) {
		this.renderValues(profile, this.directives.profile);
		if( this.config.client.type && ! this.config.client.deviceid )
			this.profiles.get(this.model.config.client.type).then((d)=>this.saveMeta(d));
	}
	saveMeta(profile) {
		this.model.profile = profile;
		var c = this.config.client.meta;
		//if( ! this.config.client.deviceid ) return;
		if( profile && profile.meta && typeof profile.meta === typeof {}) {
			var m = profile.meta;
			assign(c, 'engine'         , m.engine);
			if (m.processes && c.processes) {
				assign(c.processes, 'log',     m.processes.log);
				assign(c.processes, 'logjoin', m.processes.logjoin);
				assign(c.processes, 'dailyusage'  , m.processes.dailyusage);
				assign(c.processes, 'multirate', m.processes.multirate);
			}
			assign(c, 'feeds'          , m.feeds);
			assign(c, 'inputs'         , m.inputs);
			$one('#multirate').disabled = !this.config.client.meta.processes ||
						!this.config.client.meta.processes.multirate;
		} else {
			delete c['engine'];
			c.feeds = {};
			c.inputs = {};
			c.processes = {};
			$one('#multirate').disabled = true;
		}
	}
	renderStatus(status, button, refresh) {
		if( button ) spin(button, false);
		$one('#service-enable').dataset.status = status.enabled ? 'on' : 'off';
		$one('#service-start').dataset.status = status.running ? 'on' : 'off';
		$one('#service-restart').disabled = status.running ? null : 'disabled';
		if( refresh ) setTimeout(()=>this.daq.status().then(status=>this.renderStatus(status)), 500);
		if( UI.alive ) return;
		UI.alive = true;
		$for('.daq', (btn)=>btn.disabled=null);
	}
	api_help() {
		window.open(this.config.server.urls.api_help,'_blank');
	}
	register() {
		var frame = $one('#emon');
		var url = $one('#server_url').value
		$one('#capture').addEventListener('click', ()=> frame.src = '', false);
		$one('.xclose').addEventListener('click', ()=> frame.src = '', false);
		if( frame ) {
			frame.src = this.config.server.urls.register;
			frame.contentWindow.focus();
			frame.onblur = ()=>()=> {frame.src=''};
			frame.contentWindow.addEventListener('blur', ()=> {frame.src=''}, true);
		}
	}
}

class DeviceEditor {
	constructor(owner, containerselector) {
		var de = this;
		this.owner = owner;
		this.groupcontrol =  'select.device-model';
		this.inputname = 'input.device-name';
		this.inputcheckbox = '.device-inputs-field';
		this.inputs = new Msdl();
		var switchgroup = this.inputs.switchgroup;
		this.inputs.switchgroup = function(e) { switchgroup.apply(this, e); de.switchgroup(this); }
		this.attach(containerselector);
	}
	attach(containerselector) {
		var de = this;
		this.inputs.attach(containerselector, this.groupcontrol);
		$for(containerselector + ' ' + this.inputname, a=> a.onchange=function(e) { de.namechanged(this, e)});
		$for(containerselector + ' .msdl-selection-control', a=>a.onchange=function(e) { de.inputchanged(this, e)});
		$for(containerselector + ' .button-apply', a=>a.onclick=function(e) { de.test(this)});
		$for(containerselector + ' .button-remove', a=>a.onclick=function(e) { de.remove(this)});
	}
	switchgroup(control) {
		this.owner.removeInputs(control.dataset.device);
		const d = control.dataset;
		if( ! control.dataset.defaultmade ) {
			control.dataset.defaultmade = this.owner.addDefault(control.value, control.dataset.device);
		}
	}
	namechanged(control) {
		this.owner.renameInputs(control.dataset.device, control.value);
	}
	inputchanged(control) {
		control.dataset.inputid = this.owner.updateInput(
			control.dataset.inputid, control.dataset.device, control.dataset.unit, control.dataset.name, control.checked);
	}
	test(control) {
		this.owner.testDevice(control.dataset.device)
	}
	remove(control) {
		this.owner.removeDevice(control.dataset.device);
	}
}

class FeedBuilder {
	constructor() {
		this.REALTIME      = 'DataType::REALTIME';
		this.ENGINE        = 0;
		this.CREATE        = 'create';
		this.DAILY         = 'DataType::DAILY';
		this.FEEDID        = 2;
		this.METER2MRKWHD  = null;
		this.KWHD2COST     = null;
		this.NAME_ARG      = '{0}';
		this.KWHD_ARG      = '{0}d';
		this.MRKWHD_ARG    = '{0}r';
		this.TAG_ARG       = '{1}';
		this.NODE_ARG      = '{2}';
		this.PHPTIMESERIES = 2;
		this.processes = {
			log : 'process__log_to_feed',
			logjoin: 'process__log_to_feed_join',
			dailyusage: 'process__kwh_to_kwhd',
			multirate: null,
			dailycost: null,
		}
	}
	init(meta) {
		if(meta) {
			this.ENGINE = meta.engine || this.ENGINE;
			this.processes = meta.processes || this.processes;
		}
		this.descriptions = {
			kWh : "Electricity meter",
			kWhr: "Reactive energy meter",
			W   : "Power consumption",
			kW  : "Power consumption",
			VAR : "Reactive power",
			A   : "Current consumption",
			Hz  : "Mains frequency",
			V   : "Mains voltage",
			_   : "Input",
		}
	}
	input_template(unit, processes) {
		return {
		  name        : this.NAME_ARG,
		  node        : this.NODE_ARG,
		  description : this.descriptions[unit] || this.descriptions._,
		  processList : processes.map(proc=>(this.processes[proc] ? {process: this.processes[proc],
			  			arguments: {type : this.FEEDID, value : this.NAME_ARG } } : null)),
		  action      : this.CREATE,
		  id          : -1,
		}
	}
	log(unit) {
	  return {
	      name        : this.NAME_ARG,
	      tag         : this.TAG_ARG,
	      type        : this.REALTIME,
	      engine      : this.ENGINE,
	      unit        : unit,
	      action      : this.CREATE,
	      id          : -1,
	    }
	}
	logjoin(unit) { return this.log(unit); }
	dailyusage(unit) {
	  if (this.ENGINE == 11)
		return {
		  name        : this.KWHD_ARG,
		  tag         : this.TAG_ARG,
		  type        : this.DAILY,
		  engine      : this.ENGINE,
		  unit        : unit + 'd',
		  action      : this.CREATE,
		  id          : -1,
		}
	  else
	  return {
		  name        : this.KWHD_ARG,
		  tag         : this.TAG_ARG,
		  type        : this.DAILY,
		  engine      : this.PHPTIMESERIES,
		  unit        : unit + 'd',
		  action      : this.CREATE,
		  id          : -1,
		  options     : {interval:86400},
		}
	}
	multirate(unit) {
	  return {
		  name        : this.MRKWHD_ARG,
		  tag         : this.TAG_ARG,
		  type        : this.REALTIME,
		  engine      : this.ENGINE,
		  unit        : unit+'d',
		  action      : this.CREATE,
		  id          : -1,
		}
	}
	dailycost(unit) { // implement when server side is ready
		return null;
	}

	feed_template(unit, processes) {
		return processes.map(proc=> this[proc] ? this[proc](unit) : null);
	}
	clone_and_subst(obj, ...args) {
		if( obj == null ) return null;
		var clone = Array.isArray(obj) ? [] : {};
		Object.entries(obj).forEach(o=> o[1] !== null && (clone[o[0]]
			= typeof(o[1]) == typeof({}) ? this.clone_and_subst(o[1], ...args)
			: typeof(o[1]) == typeof('') && o[1].match(/{\d}/g) ? format(o[1], ...args)
			: o[1]));
		return clone
	}

	build_input(input, nodeid) {
		const built = this.clone_and_subst(this.input_template(input.unit || '', input.processes), input.name, input.tag, nodeid);
		if( built ) built.processes = FeedBuilder.make_proclist;
		return { inputs: [built], feeds: this.clone_and_subst(this.feed_template(input.unit || '', input.processes),  input.name, input.tag, nodeid) };
	}
	merge(arr) {
		var obj = {};
		arr.forEach(a=>{for(let k in a) {
			if(! obj[k] ) obj[k] = a[k];
			else obj[k] = obj[k].concat(a[k]);
		}});
		return obj;
	}
	build(inputs, nodeid) {
		return this.merge(inputs.map(input=>this.build_input(input, nodeid)));
	}
}

FeedBuilder.make_proclist = function(feeds, procdict) {
	return this.processList.map(p=>{
		const proc = procdict && procdict[p.process];
		const procid = (proc && proc.id_num) || p.process;
		const feed = feeds.find(f=>f.name==p.arguments.value);
		const feedid = feed ? feed.id : p.arguments.value;
		return procid + ':' + feedid;
	}).join(',');
}


/** UIConfig - implements DAQEMON Configuration page																*/
class UIConfig extends UICommon {
	constructor() {
		super();
		var ui = this;
		this.identity = 0;
		this.handlers = {
			fail  : (err)=> this.showError(err),
			onstatechange : function(event) { ui.changed(this, event); return true; }
		}
		this.setupProgbarCSS();
		this.feedBuilder = new FeedBuilder();
		this.api = {};
		this.emon = { inputs: {}, feeds: [], inputlist : [] };
	}

	render(obj) { try {
		if( typeof obj != typeof {} || obj.length == 0 || ! obj.config ) return;
		this.model  = obj;
		this.config = obj.config;
		this.rebase();
		this.adjustModelList();
		this.fillProceeses();
		this.urls = this.makeURLs(this.config.server.url, this.config.server.uri);
		this.api.feed  = new EmonAPI(this.config.server, this.urls.feeds);
		this.api.input = new EmonAPI(this.config.server, this.urls.inputs, EmonAPI.inputs_composer);
		this.api.node  = new EmonAPI(this.config.server, this.urls.node);

		if( this.config.client.nodeid && this.config.server.apikey) {
			this.api.input.get(this.config.client.nodeid).then((a)=>this.gotinputs(a)).catch((e)=>this.showError(e));
			this.api.input.list().then((a)=>this.gotinputs(a)).catch((e)=>this.showError(e));
			this.api.feed.list().then((a)=>this.gotfeeds(a)).catch((e)=>this.showError(e));
		}
		var sheet = window.document.styleSheets[0];
		if( this.model.daqemon.models ) {
			for(var i in this.model.daqemon.models) {
				this.addSelectorRule(sheet, this.model.daqemon.models[i].name);
			}
			this.model.daqemon.models.unshift('');
			$p('select.device-model').render(this.model.daqemon.models, this.directives.models);
			$p('.device-inputs-field').render(this.inputlist(), this.directives.inputlist);
			$p('.input-process-field').render(this.config.processes, this.directives.processlist);
		}
		var inuse = [];
		var devices = [{template:true}];
		this.config.devices.forEach(d=>{
			inuse.push(d.slaveid);
			devices.push(d);
		})
		for(var i in this.config.interface.slaveids) {
			var id = this.config.interface.slaveids[i];
			if( ! inuse.includes(id) ) devices.push({slaveid:id});
		}
		this.config.devices_ = devices;
		$p('#container').render(this.config, this.directives.config);
		this.moveRendered($all('#devices tfoot tr:not(.template)'), $one('#devices tbody'));
		for(var k in this.config.devices) {
			var d = this.config.devices[k];
			var o = $one('#device-' + d.slaveid +' option[value="' + d.model + '"]');
			if( o ) o.selected = true;
		}
		this.config.inputs.forEach((i,pos)=>{
			//i.id = pos+1;
			var dev = this.config.devices.find(d=>i.device==d.name);
			if( dev ) {
				i.deviceid = dev.slaveid;
				$for(`#device-${dev.slaveid} .device-input[data-name="${i.input}"][data-model="${dev.model}"]`, a=>{
					a.setAttribute('checked', true);
					a.dataset.inputid = pos+1;
				});
			} else
				i.orphan = true;
			i.identifier = i.name;
			i.enableproc = UnitProcessMap[i.unit] || UnitProcessMap[''];
			i.persistent = true;
		});
		this.createInputs(this.config.inputs);
		$for('select.device-model option:not([value])', o=>o.disabled=true); // pure does not render disabled
		$for('input.unique',i=>i.addEventListener('change', unique));
		this.modifed = false;
		this.indicateChanges(this.model.staging ? "Unapplied changes" : null);
		this.enableApply();
		//this.fixAbout();
		this.init();
		$for('.state',a=>a.addEventListener('change',this.handlers.onstatechange));
		this.rendered = true;
	} catch(e) { console.log(e); }}
	init() {
		super.init();
		this.hookup();
	}
	enableApply() {
		$one('#apply').disabled = ! this.validate(false, this.config.client.deviceid, hassome(this.config.inputs));
	}
	hookup() {
		super.hookup();
		this.devices = new DeviceEditor(this, '#devices tr:not(.template)');
		this.processing = new Msdl('#inputs .input-process-field', '');
		$one('#scan').onclick = ()=> this.scan();
		$one('#slaveids').onfocus = function() { this.style = "" };
		$one('#slaveids').onchange = ()=> this.slaveid_changed();
		$one('#add-unlisted').onclick = ()=> this.addUnlisted();
		$one('#apply').onclick = ()=> this.apply();
		$one('#ok').onclick = ()=> this.doapply();
		$one('#cancel').onclick = ()=> this.cancel();
		$one('#close').onclick = ()=> this.cancel();
		$one('#test-results .xclose').onclick = ()=> this.closeTestData();
	}
	addSelectorRule(sheet, m) {
		sheet.insertRule(`.msdl-group-selector[value=${m}] ~ ul.selection li.model-${m} { display: block; }`, sheet.cssRules.length);
	}
	inputlist() {
		var l = this.model.daqemon.models;
		var res = []
		for(var m in l)
			if(m && typeof l[m] == typeof {} && typeof l[m].inputs == typeof {})
				for(var i in l[m].inputs) res.push(inputobject(i, l[m].name));
		return res.sort((a,b)=>a.compare(b));
	}
	adjustModelList() {
		var m = this.model.daqemon.models.filter(a=>typeof(a.name)=='string' && a.name!='SIM'); // hide SIM
		// sort alphabetically and bubble GENERIC up
		m.sort((a,b)=>a.name=='GENERIC' ? -1 : b.name=='GENERIC' ? 1 : a.name.localeCompare(b.name));
		this.model.daqemon.models = m;
	}
	poll() {
		this.daq.scan().then((scan)=>this.scanned(scan)).catch(this.handlers.fail);
	}
	scan() {
		var ifc = this.config.interface.new_rtu.join(',')
		this.daq.scan(ifc).then((scan)=>this.scanned(scan)).catch(this.handlers.fail);
		this.disableScan(true);
		spin($one('#scan'), true);
	}
	disableScan(disable) {
		var scan = $one('#scan');
		var slaveids = $one('#slaveids');
		scan.disabled = disable;
		slaveids.style = null;
		slaveids.readOnly = disable;
		if( ! disable ) spin(scan, false);
		return disable;
	}
	slaveid_changed() {
		var ids = parseIds($one('#slaveids').value);
		ids = ids.filter((id)=>!$one('.device-slave-id[value="'+id+'"]'));
		this.unlisted = ids;
		$one('#add-unlisted').disabled = ids.length == 0;
	}
	scanned(obj) {
		if( !obj ) return this.disableScan(false) || this.showError('Empty responce');
		if( ! obj.success ) return this.disableScan(false) || this.showError(obj.message);
		if( obj.done === true && Array.isArray(obj.ids) ) {
			obj.ids = obj.ids.filter((id)=>!$one('.device-slave-id[value="'+id+'"]'));
			$one('#add-unlisted').disabled = obj.ids.length == 0;
			this.unlisted = obj.ids;
		}
		if( obj.ids ) $one('#slaveids').value = obj.ids.join(' ');
		$one('#slaveids').dataset.value = (obj.done === false && obj.stat <= 100) ? obj.stat : null;
		if( this.disableScan(!obj.done) ) setTimeout(()=>this.poll(), 1000);
	}
	addUnlisted() {
		if( ! hassome(this.unlisted) ) return;
		var devices = this.unlisted.map(x=> { return {slaveid:x}; });
		devices.push({template:true});
		var rendered = $p('#devices tfoot.template').render({devices_:devices}, this.directives.devices);
		this.devices.attach('#devices tfoot.template tr:not(.template)');
		this.moveRendered($all('#devices tfoot tr:not(.template)'), $one('#devices tbody'));
		this.slaveid_changed();
	}
	moveTemplate(row) {
		var table = row.parentElement.parentElement;
		var footer = table.tFoot || table.createTFoot();
		footer.appendChild(row);
	}
	moveRendered(rows, dst) {
		$for(rows, (row) => {
			dst.appendChild(row);
			$for(row.querySelectorAll('select option:not([value])'), (o)=>{o.selected=true; o.disabled=true});
			this.showing(row);
		});
	}
	collectInputs(id, withinputs) {
		const editor = $one(`#device-name-${id}`)
		if( ! editor ) return console.log('Editor not found', `#device-name-${id}`), [];
		if( editor.validationMessage )
			return this.showError(editor.validationMessage);
		const name = editor.value;
		if( !withinputs ) return this.makeInput(name);
		return $arr(`.device-input[data-device="${id}"]:checked`).map(
			(a)=>this.makeInput(name, a.dataset.unit, id, a.dataset.inputid, a.dataset.name, a.id));
	}
	fillProceeses() {
		if( !Array.isArray(this.config.processes) ) return;
		this.processes = {};
		this.methods = {};
		this.config.processes.forEach(a=>{
			this.processes[a.id] = a;
			if( a.method )
			this.methods[a.method] = a;
		});
	}
	removeDevice(id) {
		$for(`tr[data-device="${id}"]`,a=>a.classList.add('hiding'));
		setTimeout(()=>$for(`tr[data-device="${id}"]`,a=>a.style.display = 'none'), 1000);
		this.changed();
	}
	makeInput(devname, unit, deviceid, inputid, inputname, selector) {
		var last = inputname && inputname[inputname.length-1] || "";
		last = last.toUpperCase() == last ? last : "";
		var identifier = devname + last + (unit ? "_" + unit : "");
		var tag = devname + (last ? "_" + last : "");
		var enableproc = UnitProcessMap[unit] || UnitProcessMap[''];
		var processes = this.inferProcesses(identifier, unit);
		return {
			tag        : tag,
			device     : devname,
			identifier : identifier,
			deviceid   : deviceid,
			inputid    : inputid,
			unit       : unit,
			input      : inputname,
			selector   : selector,
			enableproc : enableproc,
			processes  : processes,
			interval   : 10,
		};
	}
	inferProcesses(input, unit) {
		var remote = this.inputs && this.inputs[inputs];
		var list;
		if( ! remote || typeof remote.processList != typeof '') {
			return DefaultProcesses[unit] || DefaultProcesses[''];
		} else {
			list = remote.processList.split(',').map(a=>a.split(':')[0]);
			return list.map(p=>this.methods[p]).filter(a=>a);
		}
	}
	addDefault(model, deviceid) {
		var inps = $arr(`.msdl-selection-control[data-model="${model}"][data-device="${deviceid}"]`);
		if( inps.length > 1 ) inps = inps.filter(i=>i.dataset.name=='meter');
		if( inps.length != 1 ) return false;
		inps[0].checked = true;
		var name = $one(`.device-name[data-device="${deviceid}"]`);
		if( name && name.value ) this.renameInputs(deviceid, name.value);
		return true;
	}
	renameInputs(deviceid, name) {
		var inputs = this.collectInputs(deviceid, true);
		if( ! inputs ) return;
		inputs = inputs.filter(input=>!(input.inputid && this.updateInputs(input)));
		if( inputs.length ) this.createInputs(inputs);
	}
	removeInputs(deviceid) {
		$for(`#inputs tr[data-device="${deviceid}"]`, a=>this.hiding(a));
		this.changed();
	}
	createInputs(inputs) {
		inputs.forEach((input, index)=>{
			var id = this.createInput(input, index==inputs.length-1);
			var deviceinput = $one(`#${input.selector}`);
			if( deviceinput ) deviceinput.dataset.inputid = id;
		});
		if( inputs.length && this.rendered ) this.changed();
	}
	updateInputs(input) {
		var updated = false;
		$for(`#identifier-${input.inputid}`,(a)=>{updated=true; a.value = input.identifier; a.dataset.name=input.device});
		$for(`#input-name-${input.inputid}:not([data-edited])`,a=>a.value = input.tag);
		if( updated ) this.changed();
		return updated;
	}
	updateInput(inputid, deviceid, unit, inputname, active) {
		if( inputid && ! active ) {
			$for('tr#input-' + inputid, a=>this.hiding(a));
			this.changed();
			return inputid;
		}
		if( inputid ) {
			//update
			$for('tr#input-' + inputid, a=>this.showing(a));
			this.changed();
			return inputid;
		}
		var obj = this.collectInputs(deviceid);
		if( obj && obj.identifier ) {
			obj = this.makeInput(obj.tag, unit, deviceid, inputid, inputname);
			return this.createInput(obj, true);
		}
		return '';
	}
	createInput(obj, commit) {
		obj.id = ++this.identity;
		$p('#inputs tfoot.template').render({inputs:[obj,{template:true}]}, UI.directives.inputs);
		obj.enableproc.forEach(p=>$for(`#inputs tfoot.template #input-processes-${obj.id} .process-${p}`,c=>delete c.dataset.disabled));
		obj.processes.forEach(p=>$for(`#inputs tfoot.template #msdl-item-${p}-${obj.id}`, c=>c.setAttribute('checked',true)));
		if( commit ) {
			$for('#inputs tfoot tr:not(.template) .state',a=>a.onchange=this.handlers.onstatechange);
			this.processing.attach('#inputs tfoot tr:not(.template)');
			this.moveRendered($all('#inputs tfoot tr:not(.template)'), $one('#inputs tbody'));
		}
		if( this.rendered ) this.changed();
		return obj.id;
	}
	hiding(element) {
		if( element.timer ) clearTimeout(element.timer);
		element.classList.add('hiding');
		element.timer = setTimeout(()=>element.style.display = 'none', 1000);
	}
	showing(element) {
		if( element.timer ) clearTimeout(element.timer);
		element.style.display = '';
		element.classList.remove('hiding');
	}
	gotinputs(obj) {
		if( ! obj || typeof obj === typeof '') {
			return this.showError(obj);
		}
		if( Array.isArray(obj) )
			this.emon.inputlist = obj;
		else
			this.emon.inputs = obj;
		if( this.emon.inputlist.length && Object.keys(this.emon.inputs).length ) {
			/* two different API calls returns different representations of input,
			 * here we copy input.id from inputs in the list to the inputs in the map */
			this.emon.inputlist.forEach(input=>{
				if( input.nodeid == this.config.client.nodeid && this.emon.inputs.hasOwnProperty(input.name) ) {
					this.emon.inputs[input.name].id = input.id;
				}
			});
		}
	}
	gotfeeds(obj) {
		if( ! obj || typeof obj === typeof '') {
			return this.showError(obj);
		}
		this.emon.feeds = obj;
		new EmonAPI(this.config.server, this.urls.processes).list().then(r=>this.gotprocesses(r)).catch(e=>this.showError(e));
	}
	gotprocesses(obj) {
		if( ! obj || typeof obj === typeof '') {
			return this.showError(obj);
		}
		this.emon.processes = obj;
	}
	failed(err) {
		success(spin($one('#save'), false),false);
		this.showError(err);
	}
	changed(control, event) {
		if( control && control.dataset ) control.dataset.edited = true;
		if( ! this.unsaved ) $one('#apply').disabled = true;
		this.indicateChanges("Unsaved changes");
		this.unsaved  = true;
		this.config.valid = false;
		this.setSaveAction(true);
	}
	processesDiffer(inpa, inpb) {
		return ! inpb || inpa.processes(this.emon.feeds, this.emon.processes) != inpb.processList;
	}
	save(persist) {
		var invalid = null;
		$for('.unique[value]:invalid',e=>{e.classList.add('invalid'); invalid = e});
		if( invalid ) {
			window.alert("Cannot save configuration.\n" + invalid.validationMessage);
			invalid.focus();
			return;
		}
		const cfg = this.collect(this.directives.collect);
		cfg.inputs && cfg.inputs.forEach(i=>i.qos=i.qos^0);
		cfg.valid = this.config.valid;
		spin($one('#save'), true);
		this.daq.saveconfig(cfg, persist).then((r)=>this.saved(r, persist)).catch(e=>this.failed(e));
	}
	saved(result, persist) {
		success(spin($one('#save'), false),result && result.success);
		if (! result ) return
		if( result.success ) {
			this.config.devices = result.config.devices;
			this.config.inputs = result.config.inputs;
			this.enableApply();
			if( result.message ) this.showMessage(result.message);
		} else {
			if( result.message ) this.showError(result.message);
		}
		this.unsaved = false;
		this.indicateChanges(persist ? null : "Unapplied changes");
		this.setEraseAction(persist);
		this.setSaveAction();
	}
	apply() {
		this.feedBuilder.init(this.config.client.meta);
		const emon = this.feedBuilder.build(this.config.inputs, this.config.client.nodeid);
		if( ! emon.inputs || ! emon.inputs.length ) return this.showMessage("No inputs configured");
		var messages = [];
		emon.inputs = emon.inputs.filter(i=>i);
		emon.newinputs = emon.inputs.filter(i=>{
			const found = this.emon.inputs[i.name];
			i.updated = this.processesDiffer(i, found);
			if( i.updated || !found )
				messages.push({name:i.name, class:'input', action: (found? 'update' : 'create')});
			i.id = found ? found.id : i.id;
			return !found;
		});
		emon.inputs = emon.inputs.filter(i=>i.updated);
		emon.feeds = emon.feeds.filter(i=>{
			if( ! i ) return false;
			const found = this.emon.feeds.find(f=>f.name==i.name);
			messages.push({name:i.name, class: 'feed', action: (found? 'use' : 'create')});
			i.id = found ? found.id : i.id;
			return !found;
		});
		this.todo = emon;
		$for('#action-list .action-preview', (e,i)=> i&&e.parentNode.removeChild(e));
		$for('#action-list .action-status',e=>{e.classList.remove('success'); e.classList.remove('failure'); });
		$p('#action-list').render(messages, this.directives.actionspreview);
		$one('#ok').style.display = 'block';
		$one('#close').style.display = 'none';
		this.showModal('#actions-preview', true);
	}
	cancel() { this.showModal('#actions-preview', false); }
	indicate(id, cls, ok, message) {
		const success = ok ? 'success' : 'failure';
		$for(`.action-preview[data-id="${id}"][data-class="${cls}"] .action-status`,a=>{
			a.classList.add(success);
			a.title = message || '';
		})
	}
	async doapply() {
		if( this.todo.newinputs.length ) {
			const inputs = {};
			this.todo.newinputs.forEach(i=>inputs[i.name]=null);
			var res = await this.api.input.submit(this.config.client.nodeid, inputs);
			// in this case emon returns json with content type plain/text, trying to parse it
			if( typeof res != typeof {} ) try { res = JSON.parse(res); } catch(e){};
			if( (typeof res == typeof '') || ! res.success) this.showError(res.message || res);
			const list = await this.api.input.list();
			this.gotinputs(list);
			this.todo.newinputs.forEach(input=>{
				const created = list.find(i=>i.name===input.name && i.nodeid===this.config.client.nodeid);
				const success = created ? 'success' : 'failure';
				input.id = (created && created.id) || null;
				if( created ) this.emon.inputs[created.name] = created;
				this.indicate(input.name, 'input', created);
			});
		}
		this.api.feed.createAll(this.todo.feeds, (feed, res)=>{
			if( feed === null && res === null ) return this.createProcesses();
			if( res.success ) {
				feed.id = res.feedid;
				this.emon.feeds.push(feed);
			} else
				this.showError(res.message + ':' + feed.name);
			this.indicate(feed.name, 'feed', res.success, res.message);
		});
	}
	async createProcesses() {
		for(const input of this.todo.inputs) {
			if( input.id ) {
				const res = await this.api.input.process.set(input.id,input.processes(this.emon.feeds, this.emon.processes));
				if( typeof res == typeof '' || ! res.success) this.showError(res.message || res);
				const success = res.success ? 'success' : 'failure';
				this.indicate(input.name, 'input', res.success, res.message);
				input.processList.forEach(p=>this.indicate(p.arguments.value, 'feed', res.success, res.message));
			}
		}
		this.done();
	}
	done() {
		this.config.valid = this.validate(false, this.config.client.deviceid, hassome(this.config.inputs));
		this.setSaveAction();
		$one('#ok').style.display = 'none';
		$one('#close').style.display = 'block';
	}
	testDevice(slaveid) {
		const modelselect = $one(`select.device-model[data-device="${slaveid}"]`);
		if( ! modelselect ) return this.showError("UI error: missing model selector");
		const inputs = $arr(`.device-input[data-device="${slaveid}"]:checked`).map(a=>a.dataset.name);
		spin($one(`.button-apply[data-device="${slaveid}"]`), true);
		this.daq.test(this.config.interface, slaveid, modelselect.value, inputs)
			.then(r=>this.showTestData(slaveid, r))
			.catch(e=>this.showTestData(slaveid, e));
	}
	showTestData(slaveid, data) {
		spin($one(`.button-apply[data-device="${slaveid}"]`), false);
		if( ! data.success ) return this.showError(data.message || data);
		$for('#test-data .test-result', (e,i)=> i&&e.parentNode.removeChild(e));
		$for('#test-data .test-status',e=>{e.classList.remove('success'); e.classList.remove('failure'); });

		$p('#test-data').render(data.inputs, this.directives.testresults);
		this.showModal('#test-results', true);
	}
	closeTestData() { this.showModal('#test-results', false); }
	showModal(selector, show) {
		if( show ) {
			$one(selector).classList.add('modal');
			setTimeout(()=>$one(selector).style.opacity = 1, 50);
		} else {
			$one(selector).style.opacity = 0;
			setTimeout(()=>$one(selector).classList.remove('modal'), 300);
		}
	}
	erased(data, erased) {
		if( ! erased ) return super.erased(data, erased);
		this.showMessage("Configuration erased, opening Setup");
		this.forward('setup');
	}
}

const InputClasses = {
	meter   : { unit: 'kWh', lunit: "kWh", description: "Electricity meter" },
	meter_r : { unit: 'kWhr',lunit: "kWhr",description: "Reactive power meter" },
	power   : { unit: 'W',   lunit: "W",   description: "Active power" },
	reactive: { unit: 'VAR', lunit: "VAR", description: "Reactive power" },
	voltage : { unit: 'V',   lunit: "V",   description: "Voltage" },
	current : { unit: 'A',   lunit: "A",   description: "Current" },
	frequency:{ unit: 'Hz',  lunit: "Hz",  description: "Frequency" },
	factor  : { unit: '',    lunit: "",    description: "Power factor" },
	pulse   : { unit: 'PC',  lunit: "PC",  description: "Count of meter pulses" },
	charge  : { unit: 'Ah',  lunit: "Ah",  description: "Estimated battery charge" },
};

const UnitProcessMap = {
	kWh: ['logjoin', 'dailyusage', 'multirate' /*, 'dailycost'*/],
	kWhr: ['logjoin'],
	charge: ['logjoin'],
	'': ['log'],
};

const DefaultProcesses = {
		kWh: ['logjoin', 'dailyusage'],
		kWhr: ['logjoin'],
		charge: ['logjoin'],
		'': ['log'],
	};


/** UIStatus - implements Daqemon Status page																			*/
class UIStatus extends UICommon {
	constructor() {
		super();
		this.rest = new LuciAPI('/cgi-bin/luci/admin/daqemon');
	}
	render(obj) {
		this.model = obj;
		this.config = obj.config;
		this.api = new EmonAPI(this.config.server, this.config.server.url);
		this.api.version().then(v=>this.showVersion(v)).catch(e=>this.showOutage(e));
		this.rest.log().then(l=>this.renderLog(l));
		this.daq.queuelen().then(r=>this.renderQueueLen(r))
		$one('.service-status').dataset.status = Object.keys(obj.service).filter(k=>obj.service[k]).join('-');
		$p('#data').render(this.model, this.directives);
		if( ! (obj.data && obj.data.length > 0) ) {
			$one('#recent-samples-label').style.display = 'none';
			$one('#meta').classList.add('empty');
		}
		this.showPort(obj.port);
	}
	showVersion(version) {
		$one('.server-status').dataset.status='ok';
		$one('#server-ok').innerText = version;
	}
	showOutage(error) {
		$one('.server-status').dataset.status='error';
		$one('#server-error').innerText = error.message || ('' + error);
	}
	showPort(port) {
		const dev = $one('#port-dev');
		dev.innerText = port.dev || '--';
		if( ! port.available ) dev.className = 'error';
	}
	renderQueueLen(res) {
		if( res.success ) {
			$one('.queue-status').dataset.status = res.queue == 0 ? 'ok' : '';
			$one('#queue-length').innerText = res.queue;
		} else {
			$one('.queue-status').dataset.status = error;
			const ok = $one('#queue-ok');
			ok.className = 'error';
			ok.innerText = res.message || 'ERROR';
		}
	}
	renderLog(log) {
		const lines = typeof(log) == typeof('') ? log.split('\n') : [''+log];
		function colorize(p){const m = p.item.match(/daemon.(\w+)/); return m ? (' log-' + m[1]):''};
		$one('.log-lines').style.maxWidth = 'calc(' + Math.floor($one('#error-log').clientWidth) + 'px - 0.8em)';
		$p('.log-lines').render(lines, {'.log-line' : { 'p<-': {'.' : 'p', '@class+' : colorize }}});
	}
};

/** UICharts - implements Daqemon Charts page																			*/
class UIDashboard extends UICommon {
	constructor() {
		super();
	}
	render(obj) {
		this.model = obj;
		if( obj.server.url ) {
			$one('#manage').href = obj.server.url + obj.server.uri.dashboard + '/list';
			if( this.model.server.apikey && this.model.server.uri.dashboard ) {
				new EmonAPI(this.model.server, this.model.server.url + this.model.server.uri.dashboard).list().then(list=>this.renderList(list));
			} else {
				this.renderList([{id:0,name: "-- configuration is not complete --"}]);
				$one('#dashboard').disabled = true;
			}
		} else {
			$one('#manage').disabled = true;
			$one('#apply').disabled = true;
		}
		this.hookup();
		window.parent.document.querySelector('#alt').style.display='none';
	}
	renderList(list) {
		if( Array.isArray(list) ) list.forEach(a=>a.selected = this.makeURL(a.id) == this.model.url);
		$p('#dashboard').render(list,this.directives);
		$one('#apply').disabled = ($one('#dashboard').value ^ 0) == 0;
	}
	reloadList() {
		if( this.model.server.apikey && this.model.server.uri.dashboard ) {
			$for('#dashboard option', (e,i)=> i&&e.parentNode.removeChild(e));
			new EmonAPI(this.model.server, this.model.server.url + this.model.server.uri.dashboard).list().then(list=>this.renderList(list));
		}
	}
	hookup() {
		$one('#apply').onclick = e=>this.apply();
		$one('#manage').onblur = e=>this.reloadList();
	}
	makeURL(id) {
		return this.model.server.url + this.model.server.uri.dashboard + 'view?id=' + id + '&embed=1&apikey=' + this.model.server.apikey
	}
	async apply() {
		const id = $one('#dashboard').value ^ 0;
		if( id == 0 ) return;
		const url = this.makeURL(id);
		const res = await this.daq.dashboard(url);
		if( res.success ) window.parent.location.reload(true);
	}
};

/** Rendering helpers 																							*/
function _null() { return null; }
function traverse(obj, path) {
	return (! path || ! obj || path.length == 0) ? obj :
		(path.length == 1 ? obj[path[0]] : traverse(obj[path[0]],path.slice(1)));
}
function _checked(path) {
	return function(a) {
		return traverse(a, path.split('.')) ? true : null;
	}
}
function _notchecked(path) {
	return function(a) {
		return traverse(a, path.split('.')) ? null : true;
	}
}

function _item(path,index) {
	return function(a) {
		var arr = traverse(a, path.split('.'));
		return arr ? arr[index] : null;
	}
}

function _when(match) {
	return typeof(match)=='function' ? (a)=> match(a.item) : (a)=> a.item == match;
}

function _option(match) {
	return { 'p<-' : { '.' : 'p', '@value': 'p', '@selected' : _when(match) }};
}

function asint(a, v) {
	return Number.isInteger(a) ? a : v;
}

function inputclass(inp) {
	var last = inp[inp.length-1];
	return last.toUpperCase() == last ? inp.substr(0,inp.length-1) : inp;
}

function compareinput(that) {
	if(!this.model || ! this.name) return 1;
	if( that.model != this.model ) return this.model.localeCompare(that.model);
	if( this.name == 'meter') return -1;
	if( that.name == 'meter') return 1;
	return this.name.localeCompare(that.name);
}

function inputobject(inp, model) {
	var classname = inputclass(inp);
	var clas = InputClasses[classname] || {};
	return { name: inp, class: classname, model: model, unit: clas.lunit || clas.unit, description: clas.description,
		compare : compareinput }
}

function template_class(c) {
	return c.item.template ? 'template' : null;
}

function is_required(c) {
	return c.item.template ? false : true;
}

function input_class(c) {
	return c.item.template ? 'template' : (c.item.orphan ? 'orphan' : null);
}

function test_status(c) {
	return Number(c.item) === c.item ? ' success' : ' failure';
}

function spin(e, on) {
	e.classList.remove('success');
	e.classList.remove('failure');
	if( on ) e.classList.add('spin');
	else e.classList.remove('spin');
	return e;
}
function success(e, success) {
	success = success ? 'success' : 'failure';
	e.classList.add(success);
	window.setTimeout(()=>e.classList.remove(success),2000);
	return e;
}
function assign(dst, prop, val) {
	if( val === undefined ) delete dst[prop];
	else dst[prop] = val;
}
function unique() {
	const sel = this.tagName + '.' + this.classList[0] + ':not([id="'+ this.id +'"])';
	const other = this.value && $arr(sel).find(a=>a.value == this.value);
	if( ! other ) this.classList.remove('invalid');
	this.setCustomValidity(other ? "Device name is not unique:'" + this.value + "'" : "");
}
function merge(dst, src, depth) {
	if( depth === undefined ) depth = Infinity
	for(var k in src) {
		if( typeof(dst[k]) == typeof{} && typeof(src[k]) == typeof{} && depth > 0 )
			merge(dst[k], src[k], depth - 1);
		else
			if (dst[k] === undefined)
				dst[k] = src[k];
	}
}
function toggle(checkbox) { checkbox.checked = ! checkbox.checked }
function parseIds(ids) {
	if( ! ids ) return [];
	return ids.split(' ').map((a)=>parseInt(a)).filter((a)=>!isNaN(a));
}
function hassome(array) { return array && array.length > 0; }

