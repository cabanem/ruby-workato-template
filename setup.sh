#!/bin/bash

# Workato Development Setup Script
# Run this after your devcontainer starts: ./setup.sh

set -e  # Exit on error

echo "🚀 Starting Workato Development Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if workato-connector-sdk is installed
echo "Checking Workato SDK installation..."
if gem list workato-connector-sdk -i > /dev/null 2>&1; then
    print_status "Workato Connector SDK is installed"
else
    print_warning "Installing Workato Connector SDK..."
    gem install workato-connector-sdk
    print_status "Workato Connector SDK installed"
fi

# Create standard project structure if it doesn't exist
echo -e "\nSetting up project structure..."

# Create directories
directories=(
    "connectors"
    "test"
    "test/fixtures"
    "test/fixtures/vcr_cassettes"
    "docs"
    "scripts"
    ".workato"
)

for dir in "${directories[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        print_status "Created directory: $dir"
    else
        echo "  Directory exists: $dir"
    fi
done

# Create a sample Gemfile if it doesn't exist
if [ ! -f "Gemfile" ]; then
    print_warning "Creating Gemfile..."
    cat > Gemfile << 'EOF'
source 'https://rubygems.org'

# Workato SDK
gem 'workato-connector-sdk'

# Testing
group :test do
  gem 'rspec', '~> 3.12'
  gem 'vcr', '~> 6.2'
  gem 'webmock', '~> 3.19'
  gem 'dotenv', '~> 2.8'
end

# Development tools
group :development do
  gem 'pry'
  gem 'pry-byebug'
  gem 'awesome_print'
end

# HTTP clients (often needed for connectors)
gem 'httparty', '~> 0.21'
gem 'faraday', '~> 2.7'
EOF
    print_status "Created Gemfile"
    
    echo "Installing gems..."
    bundle install
    print_status "Gems installed"
else
    print_status "Gemfile already exists"
fi

# Create a sample connector template if no connectors exist
if [ -z "$(ls -A connectors 2>/dev/null)" ]; then
    print_warning "Creating sample connector template..."
    cat > connectors/sample_connector.rb << 'EOF'
{
  title: "Sample Connector",
  
  connection: {
    fields: [
      {
        name: "api_key",
        label: "API Key",
        hint: "Your API key from the service",
        optional: false,
        control_type: "password"
      },
      {
        name: "subdomain",
        label: "Subdomain",
        hint: "Your account subdomain (e.g., 'mycompany')",
        optional: false
      }
    ],
    
    authorization: {
      type: "custom_auth",
      
      apply: lambda do |connection|
        headers("Authorization": "Bearer #{connection['api_key']}")
      end
    },
    
    base_uri: lambda do |connection|
      "https://#{connection['subdomain']}.example.com/api/v1"
    end
  },
  
  test: lambda do |connection|
    get("/ping")
  end,
  
  actions: {
    # Add your actions here
    get_record: {
      title: "Get record",
      subtitle: "Retrieves a single record by ID",
      
      input_fields: lambda do
        [
          { name: "id", type: "string", optional: false }
        ]
      end,
      
      execute: lambda do |connection, input|
        get("/records/#{input['id']}")
      end,
      
      output_fields: lambda do |object_definitions|
        object_definitions["record"]
      end
    }
  },
  
  triggers: {
    # Add your triggers here
  },
  
  object_definitions: {
    record: {
      fields: lambda do
        [
          { name: "id", type: "string" },
          { name: "name", type: "string" },
          { name: "created_at", type: "datetime" },
          { name: "updated_at", type: "datetime" }
        ]
      end
    }
  }
}
EOF
    print_status "Created sample connector template"
fi

# Create testing helper script
cat > scripts/test_connector.sh << 'EOF'
#!/bin/bash
# Helper script to test a connector

if [ -z "$1" ]; then
    echo "Usage: ./scripts/test_connector.sh <connector_name>"
    echo "Example: ./scripts/test_connector.sh sample_connector"
    exit 1
fi

CONNECTOR_PATH="connectors/$1.rb"

if [ ! -f "$CONNECTOR_PATH" ]; then
    echo "Error: Connector file not found: $CONNECTOR_PATH"
    exit 1
fi

echo "Testing connector: $1"
echo "------------------------"

# Check syntax
echo "Checking syntax..."
ruby -c "$CONNECTOR_PATH"

# Run SDK checks
echo -e "\nRunning SDK validation..."
workato exec check "$CONNECTOR_PATH"

echo -e "\nTesting complete!"
EOF
chmod +x scripts/test_connector.sh
print_status "Created test helper script"

# Create a push script for Workato
cat > scripts/push_connector.sh << 'EOF'
#!/bin/bash
# Push connector to Workato account

if [ -z "$1" ]; then
    echo "Usage: ./scripts/push_connector.sh <connector_file>"
    exit 1
fi

if [ -z "$WORKATO_API_TOKEN" ]; then
    echo "Error: WORKATO_API_TOKEN environment variable not set"
    echo "Set it with: export WORKATO_API_TOKEN='your-token-here'"
    exit 1
fi

echo "Pushing connector to Workato..."
workato push -t "$WORKATO_API_TOKEN" -f "$1"
EOF
chmod +x scripts/push_connector.sh
print_status "Created push script"

# Create .env.example file
if [ ! -f ".env.example" ]; then
    cat > .env.example << 'EOF'
# Workato Configuration
WORKATO_API_TOKEN=your_workato_api_token_here
WORKATO_ACCOUNT_ID=your_account_id_here

# Test credentials for your connector
TEST_API_KEY=your_test_api_key
TEST_SUBDOMAIN=test_subdomain

# VCR Configuration (for recording HTTP interactions)
VCR_RECORD_MODE=once
EOF
    print_status "Created .env.example"
fi

# Create a basic RSpec configuration
if [ ! -f "spec/spec_helper.rb" ]; then
    mkdir -p spec
    cat > spec/spec_helper.rb << 'EOF'
require 'workato-connector-sdk'
require 'vcr'
require 'webmock/rspec'
require 'dotenv'

Dotenv.load

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.default_cassette_options = {
    record: ENV.fetch('VCR_RECORD_MODE', 'once').to_sym,
    match_requests_on: [:method, :uri, :body]
  }
  
  # Filter sensitive data
  config.filter_sensitive_data('<API_KEY>') { ENV['TEST_API_KEY'] }
  config.filter_sensitive_data('<SUBDOMAIN>') { ENV['TEST_SUBDOMAIN'] }
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
EOF
    print_status "Created RSpec configuration"
fi

# Create README if it doesn't exist
if [ ! -f "README.md" ]; then
    cat > README.md << 'EOF'
# Workato Connector Development

## Quick Start

1. Run the setup script (if you haven't already):
   ```bash
   ./setup.sh
   ```

2. Copy `.env.example` to `.env` and fill in your credentials:
   ```bash
   cp .env.example .env
   ```

3. Test a connector:
   ```bash
   ./scripts/test_connector.sh sample_connector
   ```

## Project Structure

```
.
├── connectors/          # Your connector files
├── test/               # Test files and fixtures
├── docs/               # Documentation
├── scripts/            # Helper scripts
└── .workato/           # Workato configuration
```

## Common Commands

### Test connector syntax
```bash
workato exec check connectors/my_connector.rb
```

### Run connector console
```bash
workato exec console connectors/my_connector.rb
```

### Push to Workato
```bash
workato push -t $WORKATO_API_TOKEN -f connectors/my_connector.rb
```

## Resources

- [Workato SDK Docs](https://docs.workato.com/developing-connectors/sdk/)
- [SDK Reference](https://docs.workato.com/developing-connectors/sdk/sdk-reference/)
EOF
    print_status "Created README.md"
fi

# Create .gitignore if it doesn't exist
if [ ! -f ".gitignore" ]; then
    cat > .gitignore << 'EOF'
# Environment variables
.env
.env.local

# Ruby
*.gem
*.rbc
/.config
/coverage/
/InstalledFiles
/pkg/
/spec/reports/
/spec/examples.txt
/test/tmp/
/test/version_tmp/
/tmp/
vendor/bundle/
.bundle/

# VCR cassettes (may contain sensitive data)
/test/fixtures/vcr_cassettes/*.yml

# Workato
.workato/settings.yml
.workato/cache/
*.encrypted

# IDE
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Logs
*.log
/log/

# Local connector testing
/sandbox/
/output/
EOF
    print_status "Created .gitignore"
fi

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo -e "\nNext steps:"
echo "  1. Copy .env.example to .env and add your credentials"
echo "  2. Check out the sample connector in connectors/sample_connector.rb"
echo "  3. Use ./scripts/test_connector.sh to test your connectors"
echo -e "\nHappy coding! 🎉"
