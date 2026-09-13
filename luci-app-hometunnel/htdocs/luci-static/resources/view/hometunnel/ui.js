/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com> */
/* hometunnel ui — 视图样式兼容层。
 *
 * 背景: 自定义主题（infinityfreedom-ng 等）不加载 LuCI 官方主题的 cascade.css,
 * 且其适配脚本 ngRender.js 只为 input.cbi-button-* 补 Bootstrap 类 —— JS 视图
 * 动态创建的 button/a/div、alert-message、label、spinning、原生 select 等
 * 全部无样式（裸灰字/透明底）。
 *
 * 本模块在视图根节点挂 .ht-ui 作用域类并注入一段补齐 CSS（配色全部取自
 * 主题自身调色板，与 ngRender 给 input 按钮映射的 Bootstrap 变体一致），
 * 使应用在任意主题下渲染一致。视图侧用法:
 *
 *   'require view.hometunnel.ui as htui';
 *   var container = E('div', {}, [...]);
 *   htui.apply(container);
 */

'use strict';
'require baseclass';

var STYLE_ID = 'ht-ui-style';

var CSS = `
/* ---- 横幅 alert-message (warning/success/error): 主题无 cascade.css ---- */
.ht-ui .alert-message{position:relative;margin:.6rem 0;padding:.65rem .95rem;border-radius:.5rem;
 border:1px solid rgba(255,255,255,.14);background:rgba(54,64,74,.9);color:#c0cbd4;font-size:13px;
 box-shadow:0 1px 3px rgba(0,0,0,.18)}
.ht-ui .alert-message p{margin:.1em 0;line-height:1.55}
.ht-ui .alert-message .btn{margin:.5rem 0 .1rem}
.ht-ui .alert-message pre{margin:.45em 0;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.08);
 border-radius:4px;padding:.45em .6em;font-size:12px;white-space:pre-wrap;color:#a9b7c6}
.ht-ui .alert-message.warning{background:linear-gradient(rgba(255,152,0,.13),rgba(255,152,0,.13)),rgba(54,64,74,.9);
 border-color:rgba(255,152,0,.38);color:#ffca7a}
.ht-ui .alert-message.success{background:linear-gradient(rgba(120,195,80,.13),rgba(120,195,80,.13)),rgba(54,64,74,.9);
 border-color:rgba(120,195,80,.38);color:#a8d97e}
.ht-ui .alert-message.error{background:linear-gradient(rgba(247,83,31,.13),rgba(247,83,31,.13)),rgba(54,64,74,.9);
 border-color:rgba(247,83,31,.42);color:#ff9d7a}
/* ---- 按钮 btn cbi-button 族: ngRender 只映射 input 标签, button/a/div 全漏 ---- */
.ht-ui .btn.cbi-button{display:inline-block;border-radius:.2rem;padding:.42rem .95rem;font-size:13px;
 line-height:1.45;cursor:pointer;user-select:none;text-decoration:none;
 background:rgba(255,255,255,.08);color:#c0cbd4;border:1px solid rgba(255,255,255,.18);
 transition:background-color .15s ease,color .15s ease,border-color .15s ease}
.ht-ui a.btn.cbi-button{text-decoration:none}
.ht-ui .btn.cbi-button:hover{background:rgba(255,255,255,.15);color:#f0f4f8}
.ht-ui .btn.cbi-button:disabled{opacity:.5;cursor:not-allowed;pointer-events:none}
.ht-ui .btn.cbi-button-apply{background:#348cd4;border-color:#348cd4;color:#fff;font-weight:600}
.ht-ui .btn.cbi-button-apply:hover{background:#2c77b4;border-color:#2c77b4;color:#fff}
.ht-ui .btn.cbi-button-save,.ht-ui .btn.cbi-button-edit{background:#45bbe0;border-color:#45bbe0;color:#fff}
.ht-ui .btn.cbi-button-save:hover,.ht-ui .btn.cbi-button-edit:hover{background:#37a6c9;border-color:#37a6c9;color:#fff}
.ht-ui .btn.cbi-button-add{background:#78c350;border-color:#78c350;color:#fff}
.ht-ui .btn.cbi-button-add:hover{background:#6ab043;border-color:#6ab043;color:#fff}
.ht-ui .btn.cbi-button-reset{background:#ff9800;border-color:#ff9800;color:#fff}
.ht-ui .btn.cbi-button-reset:hover{background:#f08c00;border-color:#f08c00;color:#fff}
.ht-ui .btn.cbi-button-negative,.ht-ui .btn.cbi-button-remove{background:#f7531f;border-color:#f7531f;color:#fff}
.ht-ui .btn.cbi-button-negative:hover,.ht-ui .btn.cbi-button-remove:hover{background:#e04a1a;border-color:#e04a1a;color:#fff}
/* ---- form 页脚 Save&Apply 下拉 (div.cbi-dropdown — ngRender 的 input 映射和
 * footer.ut 的 button 映射都漏掉它, 全主题级缺口)。它由 luci.js addFooter() 在
 * 视图渲染后追加到 #view, 位于 .ht-ui 之外; 全局规则在 SPA 下会泄漏到其他页面,
 * 用 #view:has(.ht-ui) 锚定 —— 离开本应用后 .ht-ui 消失, 规则自动失效 ---- */
.ht-ui .cbi-dropdown.cbi-button-apply,
#view:has(.ht-ui) .cbi-dropdown.cbi-button-apply{background:#348cd4;border-color:#348cd4;color:#fff;font-weight:600}
#view:has(.ht-ui) .cbi-dropdown.cbi-button-apply:hover{background:#2c77b4;color:#fff}
/* ---- 状态徽章 label: 原 running/stopped 视觉无差异 ---- */
.ht-ui .label{display:inline-block;padding:.22rem .68rem;border-radius:999px;font-size:12px;font-weight:600;
 white-space:nowrap;line-height:1.4;background:rgba(255,255,255,.08);color:#94a0ad}
.ht-ui .label.success{background:rgba(120,195,80,.18);color:#78c350}
/* ---- 复制按钮反馈 spinning: cascade.css 未加载 ---- */
.ht-ui .spinning{opacity:.55;pointer-events:none}
/* ---- 命令输出 pre / 守护日志: 终端质感 ---- */
.ht-ui pre{background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.09);border-radius:4px;
 padding:.55em .75em;color:#a9b7c6;white-space:pre-wrap}
/* ---- 原生 select (cbi-input-select): ng.css 无规则, 对齐主题下拉配色 ---- */
.ht-ui select.cbi-input-select{background:linear-gradient(#3b4651,#333d47);border:1px solid #424e5a;
 border-radius:3px;color:#c0cbd4;padding:.42rem .6rem;min-width:220px;outline:none}
.ht-ui select.cbi-input-select:focus{border-color:#348cd4}
`;

return baseclass.extend({
	/* 幂等: 注入 <style>（每会话一次）并给根节点加作用域类 */
	apply: function (root) {
		var styleEl = document.getElementById(STYLE_ID);
		if (!styleEl) {
			styleEl = document.createElement('style');
			styleEl.id = STYLE_ID;
			styleEl.textContent = CSS;
			document.head.appendChild(styleEl);
		}
		root.classList.add('ht-ui');
		return root;
	}
});
