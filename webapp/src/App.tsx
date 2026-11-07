import VerticalLayout from './components/VerticalLayout';

const App = () => (
  <VerticalLayout
    header={<h1>React on Azure Storage</h1>}
    footer={<small>Static website on Azure Blob Storage, provisioned with Terraform.</small>}
  >
    <p>
      This page is a static build served from the <code>$web</code> container of an Azure
      Storage account over HTTPS.
    </p>
  </VerticalLayout>
);

export default App;
