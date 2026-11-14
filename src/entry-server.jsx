import React from 'react';
import { renderToString } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom';
import { Shell } from './main.jsx';
export function render(path) { return renderToString(<StaticRouter location={path}><Shell /></StaticRouter>); }
