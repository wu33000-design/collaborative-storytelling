import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import NotFound from "@/pages/NotFound";
import { Route, Router as WouterRouter, Switch } from "wouter";
import AuthGate from "./components/AuthGate";
import ErrorBoundary from "./components/ErrorBoundary";
import { ThemeProvider } from "./contexts/ThemeContext";
import CreateActivity from "./pages/CreateActivity";
import Home from "./pages/Home";
import JoinActivity from "./pages/JoinActivity";
import Start from "./pages/Start";

const routerBase = import.meta.env.BASE_URL.replace(/\/$/, "") || "/";

function Router() {
  return (
    <WouterRouter base={routerBase}>
      <Switch>
        <Route path={"/"} component={Start} />
        <Route path={"/create"} component={CreateActivity} />
        <Route path={"/join"} component={JoinActivity} />
        <Route path={"/demo"} component={Home} />
        <Route path={"/404"} component={NotFound} />
        <Route component={NotFound} />
      </Switch>
    </WouterRouter>
  );
}

function App() {
  return (
    <ErrorBoundary>
      <ThemeProvider defaultTheme="light">
        <TooltipProvider>
          <Toaster />
          <AuthGate>
            <Router />
          </AuthGate>
        </TooltipProvider>
      </ThemeProvider>
    </ErrorBoundary>
  );
}

export default App;
