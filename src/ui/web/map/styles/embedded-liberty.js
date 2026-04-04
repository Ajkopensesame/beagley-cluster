window.__BEAGLEY_EMBEDDED_STYLE__ = {
  "version": 8,
  "name": "Beagley Embedded Liberty",
  "metadata": {
    "beagley:styleMode": "embedded"
  },
  "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
  "sources": {
    "openfreemap": {
      "type": "vector",
      "tiles": [
        "https://tiles.openfreemap.org/planet/latest/{z}/{x}/{y}.pbf"
      ],
      "minzoom": 0,
      "maxzoom": 14,
      "attribution": "&copy; OpenStreetMap contributors"
    }
  },
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {
        "background-color": "#dbe6ee"
      }
    },
    {
      "id": "landcover-wood",
      "type": "fill",
      "source": "openfreemap",
      "source-layer": "landcover",
      "filter": ["==", ["get", "class"], "wood"],
      "paint": {
        "fill-color": "#c9dbc1",
        "fill-opacity": 0.85
      }
    },
    {
      "id": "landuse-park",
      "type": "fill",
      "source": "openfreemap",
      "source-layer": "landuse",
      "filter": ["match", ["get", "class"], ["park", "grass", "recreation_ground"], true, false],
      "paint": {
        "fill-color": "#d4e6c8",
        "fill-opacity": 0.78
      }
    },
    {
      "id": "water",
      "type": "fill",
      "source": "openfreemap",
      "source-layer": "water",
      "paint": {
        "fill-color": "#a9d5f5"
      }
    },
    {
      "id": "waterway",
      "type": "line",
      "source": "openfreemap",
      "source-layer": "waterway",
      "paint": {
        "line-color": "#8ec5eb",
        "line-width": [
          "interpolate",
          ["linear"],
          ["zoom"],
          8, 0.5,
          14, 2.2
        ]
      }
    },
    {
      "id": "building",
      "type": "fill",
      "source": "openfreemap",
      "source-layer": "building",
      "minzoom": 13,
      "paint": {
        "fill-color": "#d7d1ca",
        "fill-opacity": 0.72
      }
    },
    {
      "id": "road-casing-major",
      "type": "line",
      "source": "openfreemap",
      "source-layer": "transportation",
      "filter": ["match", ["get", "class"], ["motorway", "trunk", "primary", "secondary"], true, false],
      "layout": {
        "line-cap": "round",
        "line-join": "round"
      },
      "paint": {
        "line-color": "#c7b5a5",
        "line-width": [
          "interpolate",
          ["linear"],
          ["zoom"],
          8, 1.4,
          13, 5.4,
          17, 14.0
        ]
      }
    },
    {
      "id": "road-major",
      "type": "line",
      "source": "openfreemap",
      "source-layer": "transportation",
      "filter": ["match", ["get", "class"], ["motorway", "trunk", "primary", "secondary"], true, false],
      "layout": {
        "line-cap": "round",
        "line-join": "round"
      },
      "paint": {
        "line-color": "#f7f1e7",
        "line-width": [
          "interpolate",
          ["linear"],
          ["zoom"],
          8, 0.8,
          13, 3.8,
          17, 10.0
        ]
      }
    },
    {
      "id": "road-casing-minor",
      "type": "line",
      "source": "openfreemap",
      "source-layer": "transportation",
      "filter": ["match", ["get", "class"], ["tertiary", "minor", "service", "street"], true, false],
      "layout": {
        "line-cap": "round",
        "line-join": "round"
      },
      "paint": {
        "line-color": "#d3c6ba",
        "line-width": [
          "interpolate",
          ["linear"],
          ["zoom"],
          11, 0.8,
          15, 3.6,
          17, 8.0
        ]
      }
    },
    {
      "id": "road-minor",
      "type": "line",
      "source": "openfreemap",
      "source-layer": "transportation",
      "filter": ["match", ["get", "class"], ["tertiary", "minor", "service", "street"], true, false],
      "layout": {
        "line-cap": "round",
        "line-join": "round"
      },
      "paint": {
        "line-color": "#ffffff",
        "line-width": [
          "interpolate",
          ["linear"],
          ["zoom"],
          11, 0.45,
          15, 2.2,
          17, 5.6
        ]
      }
    },
    {
      "id": "road-label",
      "type": "symbol",
      "source": "openfreemap",
      "source-layer": "transportation_name",
      "minzoom": 12,
      "layout": {
        "symbol-placement": "line",
        "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]],
        "text-font": ["Noto Sans Regular"],
        "text-size": [
          "interpolate",
          ["linear"],
          ["zoom"],
          12, 10,
          16, 13
        ]
      },
      "paint": {
        "text-color": "#485f74",
        "text-halo-color": "rgba(255,255,255,0.92)",
        "text-halo-width": 1.1
      }
    },
    {
      "id": "place-label",
      "type": "symbol",
      "source": "openfreemap",
      "source-layer": "place",
      "minzoom": 4,
      "layout": {
        "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]],
        "text-font": ["Noto Sans Regular"],
        "text-size": [
          "interpolate",
          ["linear"],
          ["zoom"],
          4, 10,
          8, 12,
          12, 15
        ]
      },
      "paint": {
        "text-color": "#31475a",
        "text-halo-color": "rgba(255,255,255,0.95)",
        "text-halo-width": 1.2
      }
    }
  ]
};
