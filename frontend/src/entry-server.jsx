import React from 'react';
import { renderToString } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom';
import { ContentProvider } from './cms.jsx';
import { Shell } from './main.jsx';
export function render(path) {
  return renderToString(
    <ContentProvider>
      <StaticRouter location={path}><Shell /></StaticRouter>
    </ContentProvider>,
  );
}
