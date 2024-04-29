//! Run with
//!
//! ```not_rust
//! cargo run -p example-hello-world
//! ```

use axum::{response::Html, Router, routing::get};
use axum::http::Request;
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "example_hello_world=debug,tower_http=debug".to_string()),
        )).with(tracing_subscriber::fmt::layer()).init();
    // build our application with a route
    let app = Router::new()
        .route("/", get(handler))
        .route("/*path", get(handler))
        .layer(tower_http::trace::TraceLayer::new_for_http());

    // run it
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .unwrap();
    tracing::debug!("listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

async fn handler(request: Request<axum::body::Body>) -> Html<&'static str> {
    tracing::info!("request = {:?}", request);
    Html("<h1>Hello, World!</h1>")
}