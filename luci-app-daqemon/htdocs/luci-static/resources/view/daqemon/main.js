/* main.js - UI bootstrapping
   This file is a part of DAQEMON application
   Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
   DAQEMON is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License v2
   as published by the Free Software Foundation;
   License:  https://opensource.org/licenses/GPL-2.0              */

/*
 * Function helpers
 */
function $e(sel) {
	var e = document.querySelector(sel);
	if( e ) return e;
	if( sel.startsWith('#') || sel.startsWith('.') ) {
		e = document.createElement('div');
		e[sel.startsWith('#') ? 'id' : 'className'] = sel.substr(1);
	} else
	try { e = document.createElement(sel); }
	catch(err) { e=document.createElement('div'); }
	document.body.appendChild(e);
	return e;
};

/*
 * Bootstrapping
 */
if( ! CFG ) CFG = {};
if( ! CFG.frame ) CFG.frame = "iframe";
if( ! CFG.msgbox ) CFG.msgbox = "#msgbox";
if( ! CFG.msgtext ) CFG.msgtext = "#msgtext";
try {
	var scripts = document.getElementsByTagName("script");
	var thisURL = (document.currentScript || scripts[scripts.length - 1]).src;
	var parts = (thisURL && thisURL.split("/")) || [""];
	parts[parts.length-1] = '';   // main.js
	CORS = parts.join('/');
	$e(CFG.msgtext).innerText = "Loading " + CORS + VIEW;
} catch(e) { console.log(e); };

class UIMain {
	init(data) {
		this.model = data;
		this.frame = $e(CFG.frame);
		this.msgbox = $e(CFG.msgbox);
		this.msgtext = $e(CFG.msgtext);
		if( VIEW ) {
			this.loadFrame(CORS + VIEW);
		} else {
			if( DATA.url ) this.open(DATA.url)
		}
		if( ALT ) this.createAlt(ALT);
		if( DATA.logo ) $e('#logo').className = DATA.logo;
	}
	open(url) {
		this.msgbox.style.display = 'none';
		this.msgtext.innerText = "OK";
		this.frame.addEventListener('load', function() {
			this.style.display = 'block';
			this.style.opacity = 1;
		});
		this.frame.contentWindow.location = url;
	}
	getText(url, fn, to) {
		var xhr = new XMLHttpRequest();
		xhr.onreadystatechange = function () {
			if( this.readyState == 4 ) {
				if( this.status == 200 )
		        	fn(null,this.responseText);
			}
		};
		xhr.open('GET', url);
		if( to ) {
			xhr.timeout = to;
			xhr.ontimeout = ()=>{ fn({message : url + ' is not accessible'},null); };
		}
		xhr.send(null);
	}
	loadFrame(view) {
		this.view = view;
		const origin = location.origin;
		const ui = this;
		const sameorigin = new URL(view).origin === origin;

		this.msgtext.innerText = "Loading " + this.view;
		//this.frame.contentWindow.ORIGIN = origin;
		//this.frame.contentWindow.MSGBOX = this.msgbox;
		this.frame.addEventListener('load', function() {
			this.contentWindow.ORIGIN = origin;
			this.contentWindow.MSGBOX = this.msgbox;
			if( typeof(this.contentWindow.render) === 'function' )
				this.contentWindow.render(ui.model);
			ui.msgbox.style.display = 'none';
			ui.msgtext.innerText = "OK";
			this.style.display = 'block';
			this.style.opacity = 1;
			var doc = this.contentDocument || this.contentWindow.document;
			document.title = doc.title; //TODO combine title with LuCI's
			var link = this.contentDocument.querySelector('link[rel="shortcut icon"], link[rel="icon"]');
			var fav = document.querySelector('link[rel="shortcut icon"], link[rel="icon"]');
			if( link ) {
				if ( fav ) { fav.href = link.href; fav.sizes = link.sizes; fav.type = link.type; }
				else document.head.appendChild(link.cloneNode());
			}
			if( window.ResizeObserver ) {
				ui.resizeObserver = new ResizeObserver(entries=>ui.resize(entries[0].contentRect));
				ui.resizeObserver.observe(doc.querySelector('body'));
			}
		});
		if( sameorigin ) this.open(view);
		else this.getText(this.view, function(err, data){
			if( data != null ) {
				var doc = ui.frame.contentDocument || ui.frame.contentWindow.document;
				if( doc == null ) {
					console.log("No target document");
					return;
				}
				doc.open();
				doc.write(data);
				doc.close();
			}
		}, 5000);
	}
	resize(contentRect) {
		const minPossibleHeight = 200;
		const height = Math.ceil(Math.max(minPossibleHeight, contentRect.height,
				parseInt(window.getComputedStyle(this.frame).minHeight)));
		this.frame.style.minHeight = height + "px";
	}
	onUnload(event) { if( this.frame && this.frame.contentWindow.UI ) return this.frame.contentWindow.UI.onUnload(); }
	createAlt(uri) {
		const div = $e('#alt');
		div.style.display = null;
		this.frame.style.opacity = 0;
		div.onclick = ()=>this.loadFrame(CORS+uri);
	}
}

var UI = new UIMain();
window.onload = function() { UI.init(DATA) }
window.onbeforeunload = function(e) { return UI.onUnload(e) }
