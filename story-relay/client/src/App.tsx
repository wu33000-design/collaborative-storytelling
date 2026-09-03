import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import NotFound from "@/pages/NotFound";
import { Route, Router as WouterRouter, Switch } from "wouter";
import { useHashLocation } from "wouter/use-hash-location";
import AuthGate from "./components/AuthGate";
import ErrorBoundary from "./components/ErrorBoundary";
import { ThemeProvider } from "./contexts/ThemeContext";
import Home from "./pages/Home";
import JoinActivity from "./pages/JoinActivity";
import PlatformAdmin from "./pages/PlatformAdmin";
import Start from "./pages/Start";
import StoryRoom from "./pages/StoryRoom";
import TeacherActivityDashboard from "./pages/TeacherActivityDashboard";
import TeacherDashboardIndex from "./pages/TeacherDashboardIndex";
import TeacherHub from "./pages/TeacherHub";

function Router() {
  return (
    <WouterRouter hook={useHashLocation}>
      <Switch>
        <Route path={"/"} component={Start} />
        <Route path={"/create"} component={TeacherHub} />
        <Route path={"/join"} component={JoinActivity} />
        <Route path={"/teacher"} component={TeacherDashboardIndex} />
        <Route path={"/teacher/activity/:activityId"} component={TeacherActivityDashboard} />
        <Route path={"/room/:groupId"} component={StoryRoom} />
        <Route path={"/admin"} component={PlatformAdmin} />
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
